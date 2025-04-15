// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @notice External imports
 */
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @notice Interface imports
 */
import "../interfaces/INativeStaking.sol";
import "../interfaces/IOracle.sol";

/**
 * @notice Library imports
 */
import "../libraries/StakingUtils.sol";
import "../libraries/ValidatorAddressUtils.sol";
import "../libraries/PriceConverter.sol";

/**
 * @title NativeStaking
 * @dev Implementation of native XFI staking to validators
 */
contract NativeStaking is
    INativeStaking,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /**
     * @dev State variables
     */
    // Role definitions
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant AVG_BOND_DURATION = 15 days;

    // Oracle contract for price conversion
    IOracle private _oracle;

    // Validator mappings
    mapping(string => Validator) private _validators;
    string[] private _validatorIds;

    // User stake mappings
    mapping(address user => mapping(string validatorId => UserStake))
        private _userStakes;
    mapping(address user => string[] validators) private _userValidators;
    mapping(address user => uint256 totalStaked) private _userTotalStaked;
    mapping(address user => bool emergencyWithdrawalRequested)
        private _emergencyWithdrawalRequested;

    // Time-based restrictions
    uint256 private _minStakeInterval;
    uint256 private _minUnstakeInterval;
    uint256 private _minClaimInterval;
    bool private _isUnstakePaused;

    // Contract settings
    uint256 private _minimumStakeAmount;
    uint256 private _minClaimAmount;

    /**
     * @dev Error definitions are in the interface
     */

    /**
     * @dev Event definitions are in the interface
     */

    /**
     * @dev Constructor and initialization
     */
    /**
     * @dev Initializes the contract
     * @param admin Address of the admin who will have DEFAULT_ADMIN_ROLE
     * @param minimumStakeAmount The minimum amount required for staking
     * @param oracle Address of the oracle for price conversions
     */
    function initialize(
        address admin,
        uint256 minimumStakeAmount,
        address oracle
    ) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);

        _minimumStakeAmount = minimumStakeAmount;
        _oracle = IOracle(oracle);

        _minStakeInterval = 1 days;
        _minUnstakeInterval = 1 days;
        _minClaimInterval = 1 days;
    }

    /**
     * @dev Modifiers
     */
    /**
     * @dev Modifier to check if validator ID is valid
     */
    modifier validValidatorId(string calldata validatorId) {
        if (!StakingUtils.validateValidatorId(validatorId)) {
            revert InvalidValidatorId(validatorId);
        }
        _;
    }

    /**
     * @dev Modifier to check if validator exists and is enabled
     */
    modifier validatorEnabled(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        if (bytes(_validators[normalizedId].id).length == 0) {
            revert ValidatorDoesNotExist(normalizedId);
        }
        if (_validators[normalizedId].status != ValidatorStatus.Enabled) {
            revert ValidatorNotEnabled(normalizedId);
        }
        _;
    }

    /**
     * @dev Modifier to check if validator exists
     */
    modifier validatorExists(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        if (bytes(_validators[normalizedId].id).length == 0) {
            revert ValidatorDoesNotExist(normalizedId);
        }
        _;
    }

    /**
     * @dev Modifier to check if enough time has passed since last stake
     */
    modifier stakeTimeRestriction(string calldata validatorId) {
        UserStake storage userStake = _userStakes[msg.sender][validatorId];
        if (userStake.stakedAt > 0) {
            if (block.timestamp < userStake.stakedAt + _minStakeInterval) {
                revert TimeTooShort(
                    _minStakeInterval,
                    block.timestamp - userStake.stakedAt
                );
            }
        }
        if (block.timestamp < userStake.lastUnstakedAt + _minStakeInterval) {
            revert TimeTooShort(
                _minStakeInterval,
                block.timestamp - userStake.lastUnstakedAt
            );
        }
        _;
    }

    /**
     * @dev Modifier to check if enough time has passed since last stake to allow unstake
     */
    modifier unstakeTimeRestriction(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        if (userStake.amount == 0) {
            revert NoStakeFound();
        }
        if (block.timestamp < userStake.stakedAt + _minUnstakeInterval) {
            revert TimeTooShort(
                _minUnstakeInterval,
                block.timestamp - userStake.stakedAt
            );
        }

        uint256 lastTimeCheck = userStake.lastUnstakedAt > 0
            ? userStake.lastUnstakedAt
            : userStake.stakedAt;
        if (block.timestamp < lastTimeCheck + _minUnstakeInterval) {
            revert TimeTooShort(
                _minUnstakeInterval,
                block.timestamp - lastTimeCheck
            );
        }
        _;
    }

    /**
     * @dev Modifier to check if enough time has passed since last stake to allow reward claim
     */
    modifier claimTimeRestriction(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        if (userStake.amount == 0) {
            revert NoStakeFound();
        }

        uint256 lastTimeCheck = userStake.lastClaimedAt > 0
            ? userStake.lastClaimedAt
            : userStake.stakedAt;
        if (block.timestamp < lastTimeCheck + _minClaimInterval) {
            revert TimeTooShort(
                _minClaimInterval,
                block.timestamp - lastTimeCheck
            );
        }
        _;
    }

    /**
     * @dev Modifier to prevent actions on stake with active unstake process
     */
    modifier notInUnstakeProcess(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        if (userStake.inUnstakeProcess) {
            revert UnstakeInProcess();
        }
        _;
    }

    /**
     * @dev External and public functions
     */
    /**
     * @dev Stakes native XFI to a validator
     * @param validatorId The validator identifier
     */
    function stake(
        string calldata validatorId
    )
        external
        payable
        override
        whenNotPaused
        nonReentrant
        validValidatorId(validatorId)
        validatorEnabled(validatorId)
        stakeTimeRestriction(validatorId)
        notInUnstakeProcess(validatorId)
    {
        bool isValid = msg.value >= _minimumStakeAmount;
        if (!isValid) {
            revert InvalidAmount(msg.value, _minimumStakeAmount);
        }

        if (_emergencyWithdrawalRequested[msg.sender]) {
            revert EmergencyWithdrawalInProcess();
        }

        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];

        bool isNewStake = userStake.amount == 0;
        uint256 mpxAmount = PriceConverter.toMPX(_oracle, msg.value);

        userStake.amount += msg.value;
        userStake.mpxAmount += mpxAmount;
        userStake.stakedAt = block.timestamp;
        
        
        _validators[normalizedId].totalStaked += msg.value;
        if (isNewStake) {
            _validators[normalizedId].uniqueStakers++;
            _userValidators[msg.sender].push(normalizedId);
        }

        _userTotalStaked[msg.sender] += msg.value;

        emit Staked(msg.sender, normalizedId, msg.value, mpxAmount);
    }

    /**
     * @dev Initiates unstaking of the full amount from a validator
     * @param validatorId The validator identifier
     */
    function initiateUnstake(
        string calldata validatorId
    )
        external
        override
        nonReentrant
        validValidatorId(validatorId)
        validatorExists(validatorId)
        unstakeTimeRestriction(validatorId)
        notInUnstakeProcess(validatorId)
    {
        if (_isUnstakePaused) {
            revert UnstakingPaused();
        }

        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];

        uint256 amount = userStake.amount;
        uint256 mpxAmount = userStake.mpxAmount;

        if (amount == 0) {
            revert NoStakeFound();
        }
        if (_emergencyWithdrawalRequested[msg.sender]) {
            revert EmergencyWithdrawalInProcess();
        }

        userStake.inUnstakeProcess = true;
        userStake.lastUnstakedAt = block.timestamp;
        userStake.unstakeAmount = amount;

        emit RewardClaimInitiated(msg.sender, normalizedId);
        emit UnstakeInitiated(msg.sender, normalizedId, amount, mpxAmount);
    }

    /**
     * @dev Initiates reward claim for a validator
     * @param validatorId The validator identifier
     */
    function initiateRewardClaim(
        string calldata validatorId
    )
        external
        override
        nonReentrant
        validValidatorId(validatorId)
        validatorExists(validatorId)
        claimTimeRestriction(validatorId)
        notInUnstakeProcess(validatorId)
    {
        require(
            !_emergencyWithdrawalRequested[msg.sender],
            "Emergency withdrawal in process"
        );
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );

        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        userStake.lastClaimedAt = block.timestamp;
        emit RewardClaimInitiated(msg.sender, normalizedId);
    }

    /**
     * @dev Initiates emergency withdrawal
     */
    function initiateEmergencyWithdrawal() external override nonReentrant {
        if (_userTotalStaked[msg.sender] == 0) {
            revert NoStakeFound();
        }
        if (_emergencyWithdrawalRequested[msg.sender]) {
            revert EmergencyWithdrawalInProcess();
        }

        _emergencyWithdrawalRequested[msg.sender] = true;

        emit EmergencyWithdrawalInitiated(msg.sender);
    }

    /**
     * @dev Migrates a user's stake from a deprecated validator to a new one
     * @param fromValidatorId The identifier of the deprecated validator
     * @param toValidatorId The identifier of the new validator
     */
    function migrateStake(
        string calldata fromValidatorId,
        string calldata toValidatorId
    )
        external
        override
        nonReentrant
        validValidatorId(fromValidatorId)
        validValidatorId(toValidatorId)
        validatorExists(fromValidatorId)
        validatorEnabled(toValidatorId)
        notInUnstakeProcess(fromValidatorId)
    {
        string memory normalizedFromId = StakingUtils.normalizeValidatorId(
            fromValidatorId
        );
        string memory normalizedToId = StakingUtils.normalizeValidatorId(
            toValidatorId
        );

        if (
            keccak256(bytes(normalizedFromId)) ==
            keccak256(bytes(normalizedToId))
        ) {
            revert SameValidator();
        }

        if (
            _validators[normalizedFromId].status != ValidatorStatus.Deprecated
        ) {
            revert ValidatorNotDeprecated(normalizedFromId);
        }

        UserStake storage oldStake = _userStakes[msg.sender][normalizedFromId];
        if (oldStake.amount == 0) {
            revert NoStakeFound();
        }
        if (oldStake.inUnstakeProcess) {
            revert UnstakeInProcess();
        }

        if (block.timestamp <= oldStake.stakedAt) {
            revert MigrationTimeError();
        }

        UserStake storage newStake = _userStakes[msg.sender][normalizedToId];
        bool isNewStake = newStake.amount == 0;

        uint256 migrationAmount = oldStake.amount;
        uint256 mpxAmount = oldStake.mpxAmount;

        newStake.amount += migrationAmount;
        newStake.mpxAmount += mpxAmount;
        newStake.stakedAt = block.timestamp;
        newStake.lastClaimedAt = 0;

        _validators[normalizedToId].totalStaked += migrationAmount;
        if (isNewStake) {
            _validators[normalizedToId].uniqueStakers++;
            _userValidators[msg.sender].push(normalizedToId);
        }

        _validators[normalizedFromId].totalStaked -= migrationAmount;
        _validators[normalizedFromId].uniqueStakers--;

        _removeValidatorFromUserList(msg.sender, normalizedFromId);

        oldStake.amount = 0;
        oldStake.stakedAt = 0;
        oldStake.mpxAmount = 0;
        oldStake.lastClaimInitiatedAt = 0;
        oldStake.inUnstakeProcess = false;
        oldStake.lastUnstakeInitiatedAt = 0;
oldStake.unstakeAmount = 0;

        emit StakeMigrated(
            msg.sender,
            normalizedFromId,
            normalizedToId,
            migrationAmount,
            mpxAmount
        );
    }

    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {}

    /**
     * @dev Admin functions
     */
    /**
     * @dev Sets validator status
     * @param validatorId The validator identifier
     * @param status The validator status to set
     */
    function setValidatorStatus(
        string calldata validatorId,
        ValidatorStatus status
    ) external override onlyRole(MANAGER_ROLE) validValidatorId(validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );

        if (bytes(_validators[normalizedId].id).length == 0) {
            _validators[normalizedId] = Validator({
                id: normalizedId,
                status: status,
                totalStaked: 0,
                uniqueStakers: 0
            });

            _validatorIds.push(normalizedId);

            emit ValidatorAdded(
                normalizedId,
                status == ValidatorStatus.Enabled
            );
        } else {
            _validators[normalizedId].status = status;

            emit ValidatorStatusUpdated(normalizedId, status);
        }
    }

    /**
     * @dev Pauses staking functionality
     */
    function pauseStaking() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses staking functionality
     */
    function unpauseStaking() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @dev Pauses unstaking functionality
     */
    function pauseUnstake() external onlyRole(MANAGER_ROLE) {
        _isUnstakePaused = true;
    }

    /**
     * @dev Unpauses unstaking functionality
     */
    function unpauseUnstake() external onlyRole(MANAGER_ROLE) {
        _isUnstakePaused = false;
    }

    /**
     * @dev Sets the Oracle address
     * @param oracleAddress Address of the oracle contract
     */
    function setOracle(
        address oracleAddress
    ) external override onlyRole(MANAGER_ROLE) {
        if (oracleAddress == address(0)) {
            revert ZeroAddress();
        }
        _oracle = IOracle(oracleAddress);
    }

    /**
     * @dev Sets the minimum stake amount
     * @param amount The new minimum stake amount
     */
    function setMinimumStakeAmount(
        uint256 amount
    ) external override onlyRole(MANAGER_ROLE) {
        if (amount == 0) {
            revert InvalidAmount(0, 1);
        }
        _minimumStakeAmount = amount;
    }

    /**
     * @dev Sets the minimum time between stakes
     * @param interval The new minimum interval
     */
    function setMinStakeInterval(
        uint256 interval
    ) external override onlyRole(MANAGER_ROLE) {
        _minStakeInterval = interval;
    }

    /**
     * @dev Sets the minimum time before unstake
     * @param interval The new minimum interval
     */
    function setMinUnstakeInterval(
        uint256 interval
    ) external override onlyRole(MANAGER_ROLE) {
        _minUnstakeInterval = interval;
    }

    /**
     * @dev Sets the minimum time before claim
     * @param interval The new minimum interval
     */
    function setMinClaimInterval(
        uint256 interval
    ) external override onlyRole(MANAGER_ROLE) {
        _minClaimInterval = interval;
    }

    /**
     * @dev Sets up a validator migration
     * @param oldValidatorId The source validator identifier
     * @param newValidatorId The destination validator identifier
     */
    function setupValidatorMigration(
        string calldata oldValidatorId,
        string calldata newValidatorId
    )
        external
        override
        onlyRole(MANAGER_ROLE)
        validValidatorId(oldValidatorId)
        validValidatorId(newValidatorId)
        validatorExists(oldValidatorId)
        validatorExists(newValidatorId)
    {
        string memory normalizedOldId = StakingUtils.normalizeValidatorId(
            oldValidatorId
        );
        string memory normalizedNewId = StakingUtils.normalizeValidatorId(
            newValidatorId
        );

        if (
            keccak256(bytes(normalizedOldId)) ==
            keccak256(bytes(normalizedNewId))
        ) {
            revert SameValidator();
        }

        _validators[normalizedOldId].status = ValidatorStatus.Deprecated;

        emit ValidatorStatusUpdated(
            normalizedOldId,
            ValidatorStatus.Deprecated
        );
    }

    /**
     * @dev Operator functions
     */
    /**
     * @dev Completes an unstake process
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @param amount Amount to unstake
     */
    function completeUnstake(
        address staker,
        string calldata validatorId,
        uint256 amount
    )
        external
        override
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        validValidatorId(validatorId)
        validatorExists(validatorId)
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[staker][normalizedId];

        if (!userStake.inUnstakeProcess) {
            revert NoUnstakeInProcess();
        }
        if (userStake.amount < amount) {
            revert InsufficientStake(amount, userStake.amount);
        }

        uint256 mpxAmountToUnstake = 0;
        if (userStake.amount > 0) {
            mpxAmountToUnstake =
                (userStake.mpxAmount * amount) /
                userStake.amount;
        }

        userStake.amount -= amount;
        userStake.mpxAmount -= mpxAmountToUnstake;
        userStake.inUnstakeProcess = false;
        userStake.lastUnstakedAt = block.timestamp;
        userStake.unstakeAmount = 0;

        _validators[normalizedId].totalStaked -= amount;
        if (userStake.amount == 0) {
            _validators[normalizedId].uniqueStakers--;
            _removeValidatorFromUserList(staker, normalizedId);
        }

        _userTotalStaked[staker] -= amount;

        emit UnstakeCompleted(staker, normalizedId, amount, mpxAmountToUnstake);

        (bool success, ) = staker.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    /**
     * @dev Completes a reward claim
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @param isInitiatedDueUnstake Whether the claim was initiated due to unstake
     */
    function completeRewardClaim(
        address staker,
        string calldata validatorId,
        bool isInitiatedDueUnstake
    )
        external
        payable
        override
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        validValidatorId(validatorId)
        validatorExists(validatorId)
    {
        if (msg.value == 0) {
            revert InsufficientRewards(msg.value, _minimumStakeAmount);
        }

        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[staker][normalizedId];

        if (userStake.amount == 0) {
            revert NoStakeFound();
        }

        if (userStake.inUnstakeProcess && !isInitiatedDueUnstake) {
            revert UnstakeInProcess();
        }

        uint256 rewardAmount = msg.value;
        userStake.lastClaimedAt = block.timestamp;

        (bool success, ) = staker.call{value: rewardAmount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit RewardClaimed(staker, normalizedId, rewardAmount);
    }

    /**
     * @dev Completes emergency withdrawal
     * @param staker The address of the staker
     * @param amount The amount to withdraw
     */
    function completeEmergencyWithdrawal(
        address staker,
        uint256 amount
    ) external override onlyRole(OPERATOR_ROLE) nonReentrant {
        if (!_emergencyWithdrawalRequested[staker]) {
            revert NoEmergencyWithdrawalRequested();
        }
        if (amount == 0 || amount > _userTotalStaked[staker]) {
            revert InvalidAmount(amount, _userTotalStaked[staker]);
        }

        _emergencyWithdrawalRequested[staker] = false;

        string[] memory userValidators = _userValidators[staker];

        for (uint256 i = 0; i < userValidators.length; i++) {
            string memory validatorId = userValidators[i];
            UserStake storage userStake = _userStakes[staker][validatorId];

            if (userStake.amount > 0) {
                _validators[validatorId].totalStaked -= userStake.amount;
                _validators[validatorId].uniqueStakers--;

                userStake.amount = 0;
                userStake.stakedAt = 0;
                userStake.mpxAmount = 0;
                userStake.lastClaimedAt = 0;
                userStake.inUnstakeProcess = false;
                userStake.lastUnstakedAt = 0;
            }
        }

        delete _userValidators[staker];
        _userTotalStaked[staker] = 0;

        uint256 mpxAmount = PriceConverter.toMPX(_oracle, amount);

        (bool success, ) = staker.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit EmergencyWithdrawalCompleted(staker, amount, mpxAmount);
    }

    /**
     * @dev Processes both reward claim and unstake in a single transaction
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @param unstakeAmount The amount to unstake
     * @param rewardAmount The amount of rewards to claim
     */
    function processRewardAndUnstake(
        address staker,
        string calldata validatorId,
        uint256 unstakeAmount,
        uint256 rewardAmount
    )
        external
        payable
        override
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        validValidatorId(validatorId)
        validatorExists(validatorId)
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[staker][normalizedId];

        if (!userStake.inUnstakeProcess) {
            revert NoUnstakeInProcess();
        }

        if (userStake.amount < unstakeAmount) {
            revert InsufficientStake(unstakeAmount, userStake.amount);
        }

        uint256 mpxAmountToUnstake = 0;
        if (userStake.amount > 0) {
            mpxAmountToUnstake =
                (userStake.mpxAmount * unstakeAmount) /
                userStake.amount;
        }

        if (rewardAmount > 0) {
            if (msg.value != rewardAmount) {
                revert InsufficientRewards(msg.value, rewardAmount);
            }

            // Update lastClaimedAt timestamp when claiming rewards
            userStake.lastClaimedAt = block.timestamp;

            emit RewardClaimed(staker, normalizedId, rewardAmount);
        }

        userStake.amount -= unstakeAmount;
        userStake.mpxAmount -= mpxAmountToUnstake;
        userStake.inUnstakeProcess = false;
        userStake.lastUnstakedAt = block.timestamp;
        userStake.unstakeAmount = 0;

        _validators[normalizedId].totalStaked -= unstakeAmount;
        if (userStake.amount == 0) {
            _validators[normalizedId].uniqueStakers--;
            _removeValidatorFromUserList(staker, normalizedId);
        }

        _userTotalStaked[staker] -= unstakeAmount;

        emit UnstakeCompleted(
            staker,
            normalizedId,
            unstakeAmount,
            mpxAmountToUnstake
        );

        bool transferSuccess = true;

        if (rewardAmount > 0) {
            (bool rewardSuccess, ) = staker.call{value: rewardAmount}("");
            transferSuccess = rewardSuccess;
        }

        if (transferSuccess) {
            (bool unstakeSuccess, ) = staker.call{value: unstakeAmount}("");
            transferSuccess = unstakeSuccess;
        }

        if (!transferSuccess) {
            revert TransferFailed();
        }
    }

    /**
     * @dev View functions
     */
    /**
     * @dev Gets the Oracle address
     * @return address The oracle address
     */
    function getOracle() external view override returns (address) {
        return address(_oracle);
    }

    /**
     * @dev Gets the minimum stake amount
     * @return uint256 The minimum stake amount
     */
    function getMinimumStakeAmount() external view override returns (uint256) {
        return _minimumStakeAmount;
    }

    /**
     * @dev Gets the minimum time between stakes
     * @return uint256 The minimum interval
     */
    function getMinStakeInterval() external view override returns (uint256) {
        return _minStakeInterval;
    }

    /**
     * @dev Gets the minimum unstake interval
     * @return uint256 The minimum interval
     */
    function getMinUnstakeInterval() external view override returns (uint256) {
        return _minUnstakeInterval;
    }

    /**
     * @dev Gets the minimum claim interval
     * @return uint256 The minimum interval
     */
    function getMinClaimInterval() external view override returns (uint256) {
        return _minClaimInterval;
    }

    /**
     * @dev Gets validator details
     * @param validatorId The validator identifier
     * @return Validator The validator details
     */
    function getValidator(
        string calldata validatorId
    ) external view override returns (Validator memory) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        return _validators[normalizedId];
    }

    /**
     * @dev Gets validator status
     * @param validatorId The validator identifier
     * @return ValidatorStatus The validator status
     */
    function getValidatorStatus(
        string calldata validatorId
    ) external view override returns (ValidatorStatus) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        return _validators[normalizedId].status;
    }

    /**
     * @dev Gets the total number of validators
     * @return uint256 The validator count
     */
    function getValidatorCount() external view override returns (uint256) {
        return _validatorIds.length;
    }

    /**
     * @dev Gets all validators
     * @return Validator[] array of validators
     */
    function getValidators()
        external
        view
        override
        returns (Validator[] memory)
    {
        Validator[] memory validators = new Validator[](_validatorIds.length);

        for (uint256 i = 0; i < _validatorIds.length; i++) {
            validators[i] = _validators[_validatorIds[i]];
        }

        return validators;
    }

    /**
     * @dev Gets a user's stake for a specific validator
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @return UserStake The user's stake details
     */
    function getUserStake(
        address staker,
        string calldata validatorId
    ) external view override returns (UserStake memory) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        return _userStakes[staker][normalizedId];
    }

    /**
     * @dev Gets a user's total staked amount
     * @param staker The address of the staker
     * @return uint256 The total staked amount
     */
    function getUserTotalStaked(
        address staker
    ) external view override returns (uint256) {
        return _userTotalStaked[staker];
    }

    /**
     * @dev Gets all validators a user has staked with
     * @param staker The address of the staker
     * @return string[] Array of validator identifiers
     */
    function getUserValidators(
        address staker
    ) external view override returns (string[] memory) {
        return _userValidators[staker];
    }

    /**
     * @dev Checks if unstake is in process for a validator
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @return bool Whether unstake is in process
     */
    function isUnstakeInProcess(
        address staker,
        string calldata validatorId
    ) external view override returns (bool) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        return _userStakes[staker][normalizedId].inUnstakeProcess;
    }

    /**
     * @dev Gets the unstake status and amount for a given validator
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @return inProcess Whether unstake is in process
     * @return amount The amount requested for unstake
     */
    function getUnstakeStatus(
        address staker,
        string calldata validatorId
    ) external view override returns (bool inProcess, uint256 amount) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[staker][normalizedId];
        return (userStake.inUnstakeProcess, userStake.unstakeAmount);
    }

    /**
     * @dev Checks if emergency withdrawal was requested
     * @param staker The address of the staker
     * @return bool Whether emergency withdrawal was requested
     */
    function isEmergencyWithdrawalRequested(
        address staker
    ) external view returns (bool) {
        return _emergencyWithdrawalRequested[staker];
    }

    /**
     * @dev Gets the user's status for a validator, including ability to stake, unstake, claim, and timing information
     * @param user The user address
     * @param validatorId The validator identifier
     * @return userStake The user's stake details
     * @return canStake Whether the user can stake to this validator
     * @return canUnstake Whether the user can unstake from this validator
     * @return canClaim Whether the user can claim rewards from this validator
     * @return stakeUnlockTime The timestamp when staking becomes available
     * @return unstakeUnlockTime The timestamp when unstaking becomes available
     * @return claimUnlockTime The timestamp when claiming becomes available
     */
    function getUserStatus(
        address user,
        string calldata validatorId
    )
        external
        view
        returns (
            UserStake memory userStake,
            bool canStake,
            bool canUnstake,
            bool canClaim,
            uint256 stakeUnlockTime,
            uint256 unstakeUnlockTime,
            uint256 claimUnlockTime
        )
    {
        // Normalize validator ID and get user stake info
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        userStake = _userStakes[user][normalizedId];

        // Calculate stake unlock time based on most recent stake/unstake
        uint256 stakedAtUnlock = userStake.stakedAt + _minStakeInterval;
        uint256 unstakedAtUnlock = userStake.lastUnstakedAt + _minStakeInterval;
        stakeUnlockTime = stakedAtUnlock > unstakedAtUnlock 
            ? stakedAtUnlock 
            : unstakedAtUnlock;
        
        // Calculate unstake unlock time
        if (!userStake.inUnstakeProcess) {
            uint256 lastUnstakeUnlock = userStake.lastUnstakedAt + _minUnstakeInterval;
            uint256 lastStakeUnlock = userStake.stakedAt + _minUnstakeInterval;
            unstakeUnlockTime = lastUnstakeUnlock > lastStakeUnlock 
                ? lastUnstakeUnlock 
                : lastStakeUnlock;
        } else {
            unstakeUnlockTime = userStake.lastUnstakedAt + 
                AVG_BOND_DURATION + 
                _minStakeInterval + 
                _minUnstakeInterval;
        }

        // Calculate claim unlock time
        uint256 lastTimeCheck = userStake.lastClaimedAt > 0 
            ? userStake.lastClaimedAt 
            : userStake.stakedAt;
        claimUnlockTime = lastTimeCheck + _minClaimInterval;

        // Determine available actions
        canStake = userStake.amount == 0 && 
            block.timestamp >= stakeUnlockTime;

        canUnstake = userStake.amount > 0 &&
            !userStake.inUnstakeProcess &&
            block.timestamp >= unstakeUnlockTime &&
            !_isUnstakePaused;

        canClaim = userStake.amount > 0 &&
            !userStake.inUnstakeProcess &&
            block.timestamp >= claimUnlockTime;

        return (
            userStake,
            canStake,
            canUnstake,
            canClaim,
            stakeUnlockTime,
            unstakeUnlockTime,
            claimUnlockTime
        );
    }

    /**
     * @dev Internal functions
     */
    /**
     * @dev Removes a validator from a user's list
     * @param staker The staker address
     * @param validatorId The validator ID to remove
     */
    function _removeValidatorFromUserList(
        address staker,
        string memory validatorId
    ) private {
        string[] storage userValidators = _userValidators[staker];

        for (uint256 i = 0; i < userValidators.length; i++) {
            if (
                keccak256(bytes(userValidators[i])) ==
                keccak256(bytes(validatorId))
            ) {
                userValidators[i] = userValidators[userValidators.length - 1];
                userValidators.pop();
                break;
            }
        }
    }

    /**
     * @dev Records a staking action
     * @param staker Address of the staker
     * @param validatorId Validator ID
     * @param amount Amount staked
     * @param mpxAmount MPX amount
     */
    function _recordStake(
        address staker,
        string calldata validatorId,
        uint256 amount,
        uint256 mpxAmount
    ) private {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[staker][normalizedId];

        userStake.amount += amount;
        userStake.mpxAmount += mpxAmount;
        userStake.stakedAt = block.timestamp;
        userStake.lastClaimedAt = block.timestamp;

        _validators[normalizedId].totalStaked += amount;
        if (bytes(_validators[normalizedId].id).length == 0) {
            _validators[normalizedId] = Validator({
                id: normalizedId,
                status: ValidatorStatus.Enabled,
                totalStaked: 0,
                uniqueStakers: 0
            });

            _validatorIds.push(normalizedId);

            emit ValidatorAdded(
                normalizedId,
                true
            );
        }

        _userTotalStaked[staker] += amount;
    }
}
