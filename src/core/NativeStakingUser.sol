// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @notice Library imports
 */
import "../libraries/StakingUtils.sol";
import "../libraries/PriceConverter.sol";

/**
 * @notice Contract imports
 */
import "./NativeStakingAdmin.sol";

/**
 * @title NativeStakingUser
 * @dev User operations for the NativeStaking contract
 */
abstract contract NativeStakingUser is NativeStakingAdmin {
    /**
     * @dev Stakes native XFI to a validator
     * @param validatorId The validator identifier
     */
    function stake(
        string calldata validatorId
    )
        external
        payable
        virtual
        whenNotPaused
        nonReentrant
        validValidatorId(validatorId)
        validatorExists(validatorId)
        validatorEnabled(validatorId)
        stakeTimeRestriction(validatorId)
        notInUnstakeProcess(validatorId)
    {
        if (msg.value < _minStakeAmount) {
            revert InvalidAmount(msg.value, _minStakeAmount);
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
        virtual
        nonReentrant
        validValidatorId(validatorId)
        validatorExists(validatorId)
        unstakeTimeRestriction(validatorId)
        notInUnstakeProcess(validatorId)
    {
        if (_isUnstakePaused) {
            revert UnstakingPaused();
        }

        if (_emergencyWithdrawalRequested[msg.sender]) {
            revert EmergencyWithdrawalInProcess();
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

        userStake.inUnstakeProcess = true;
        userStake.lastUnstakeInitiatedAt = block.timestamp;
        userStake.unstakeAmount = amount;

        // initiate Claim, so user receives Rewards + Staked funds after unstake 
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
        virtual
        nonReentrant
        validValidatorId(validatorId)
        validatorExists(validatorId)
        claimTimeRestriction(validatorId)
        notInUnstakeProcess(validatorId)
    {
        if (_emergencyWithdrawalRequested[msg.sender]) {
            revert EmergencyWithdrawalInProcess();
        }
        
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );

        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        userStake.lastClaimInitiatedAt = block.timestamp;
        emit RewardClaimInitiated(msg.sender, normalizedId);
    }

    /**
     * @dev Initiates emergency withdrawal
     */
    function initiateEmergencyWithdrawal() external virtual nonReentrant {
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
        virtual
        nonReentrant
        validValidatorId(fromValidatorId)
        validValidatorId(toValidatorId)
        validatorExists(fromValidatorId)
        validatorExists(toValidatorId)
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
        newStake.lastClaimInitiatedAt = 0;

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
     * @dev Gets the Oracle address
     * @return address The oracle address
     */
    function getOracle() external view virtual override returns (address) {
        return address(_oracle);
    }

    /**
     * @dev Gets the min stake amount
     * @return uint256 The min stake amount
     */
    function getMinStakeAmount() external view virtual override returns (uint256) {
        return _minStakeAmount;
    }

    /**
     * @dev Gets the min time between stakes
     * @return uint256 The min interval
     */
    function getMinStakeInterval() external view virtual override returns (uint256) {
        return _minStakeInterval;
    }

    /**
     * @dev Gets the min unstake interval
     * @return uint256 The min interval
     */
    function getMinUnstakeInterval() external view virtual override returns (uint256) {
        return _minUnstakeInterval;
    }

    /**
     * @dev Gets the min claim interval
     * @return uint256 The min interval
     */
    function getMinClaimInterval() external view virtual override returns (uint256) {
        return _minClaimInterval;
    }

    /**
     * @dev Gets validator details
     * @param validatorId The validator identifier
     * @return Validator The validator details
     */
    function getValidator(
        string calldata validatorId
    ) external view virtual override returns (Validator memory) {
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
    ) external view virtual override returns (ValidatorStatus) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        return _validators[normalizedId].status;
    }

    /**
     * @dev Gets the total number of validators
     * @return uint256 The validator count
     */
    function getValidatorCount() external view virtual override returns (uint256) {
        return _validatorIds.length;
    }

    /**
     * @dev Gets all validators
     * @return Validator[] array of validators
     */
    function getValidators() external view virtual override returns (Validator[] memory) {
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
    ) external view virtual override returns (UserStake memory) {
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
    ) external view virtual override returns (uint256) {
        return _userTotalStaked[staker];
    }

    /**
     * @dev Gets all validators a user has staked with
     * @param staker The address of the staker
     * @return string[] Array of validator identifiers
     */
    function getUserValidators(
        address staker
    ) external view virtual override returns (string[] memory) {
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
    ) external view virtual override returns (bool) {
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
    ) external view virtual override returns (bool inProcess, uint256 amount) {
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
    ) external view virtual override returns (bool) {
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
        virtual
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
        uint256 unstakedAtUnlock = userStake.lastUnstakeInitiatedAt + _minStakeInterval;
        stakeUnlockTime = stakedAtUnlock > unstakedAtUnlock 
            ? stakedAtUnlock 
            : unstakedAtUnlock;
        
        // Calculate unstake unlock time
        if (!userStake.inUnstakeProcess) {
            uint256 lastUnstakeUnlock = userStake.lastUnstakeInitiatedAt + _minUnstakeInterval;
            uint256 lastStakeUnlock = userStake.stakedAt + _minUnstakeInterval;
            unstakeUnlockTime = lastUnstakeUnlock > lastStakeUnlock 
                ? lastUnstakeUnlock 
                : lastStakeUnlock;
        } else {
            unstakeUnlockTime = userStake.lastUnstakeInitiatedAt + 
                AVG_BOND_DURATION + 
                _minStakeInterval + 
                _minUnstakeInterval;
        }

        // Calculate claim unlock time
        uint256 lastTimeCheck = userStake.lastClaimInitiatedAt > 0 
            ? userStake.lastClaimInitiatedAt 
            : userStake.stakedAt;
        claimUnlockTime = lastTimeCheck + _minClaimInterval;

        // Determine available actions
        canStake = !userStake.inUnstakeProcess &&
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
     * @dev Internal helper to remove validator from user's list
     */
    function _removeValidatorFromUserList(
        address staker,
        string memory validatorId
    ) internal override {
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
} 