// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/INativeStaking.sol";
import "../interfaces/IOracle.sol";
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
    // Role definitions
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // Oracle contract for price conversion
    IOracle private _oracle;
    
    // Validator mappings
    mapping(string => Validator) private _validators;
    string[] private _validatorIds;
    
    // User stake mappings
    mapping(address user => mapping(string validatorId => UserStake)) private _userStakes;
    mapping(address user => string[] validators) private _userValidators;
    mapping(address user => uint256 totalStaked) private _userTotalStaked;
    mapping(address user => bool emergencyWithdrawalRequested) private _emergencyWithdrawalRequested;
    
    // Time-based restrictions
    uint256 private _minStakeInterval;
    uint256 private _minUnstakeInterval;
    uint256 private _minClaimInterval;
    
    // Contract settings
    uint256 private _minimumStakeAmount;
    
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
        
        // Set default time intervals (1 day as default)
        _minStakeInterval = 1 days;
        _minUnstakeInterval = 1 days;
        _minClaimInterval = 1 days;
    }
    
    /**
     * @dev Modifier to check if validator ID is valid
     */
    modifier validValidatorId(string calldata validatorId) {
        require(StakingUtils.validateValidatorId(validatorId), "Invalid validator ID");
        _;
    }
    
    /**
     * @dev Modifier to check if validator exists and is enabled
     */
    modifier validatorEnabled(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        require(bytes(_validators[normalizedId].id).length > 0, "Validator does not exist");
        require(_validators[normalizedId].status == ValidatorStatus.Enabled, "Validator is not enabled");
        _;
    }
    
    /**
     * @dev Modifier to check if validator exists
     */
    modifier validatorExists(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        require(bytes(_validators[normalizedId].id).length > 0, "Validator does not exist");
        _;
    }
    
    /**
     * @dev Modifier to check if enough time has passed since last stake
     */
    modifier stakeTimeRestriction(string calldata validatorId) {
        UserStake storage userStake = _userStakes[msg.sender][validatorId];
        if (userStake.stakedAt > 0) {
            require(
                block.timestamp >= userStake.stakedAt + _minStakeInterval,
                "Time between stakes too short"
            );
        }
        _;
    }
    
    /**
     * @dev Modifier to check if enough time has passed since last stake to allow unstake
     */
    modifier unstakeTimeRestriction(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        require(userStake.amount > 0, "No stake found");
        require(
            block.timestamp >= userStake.stakedAt + _minUnstakeInterval,
            "Time since staking too short for unstake"
        );
        _;
    }
    
    /**
     * @dev Modifier to check if enough time has passed since last stake to allow reward claim
     */
    modifier claimTimeRestriction(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        require(userStake.amount > 0, "No stake found");
        require(
            block.timestamp >= userStake.stakedAt + _minClaimInterval,
            "Time since staking too short for claim"
        );
        _;
    }
    
    /**
     * @dev Modifier to prevent actions on stake with active unstake process
     */
    modifier notInUnstakeProcess(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        require(!userStake.inUnstakeProcess, "Unstake already in process");
        _;
    }

    /**
     * @dev Adds a new validator
     * @param validatorId The validator identifier
     * @param isEnabled The initial validator status Enable or Disable
     */
    function addValidator(string calldata validatorId, bool isEnabled) 
        external 
        override 
        onlyRole(MANAGER_ROLE) 
        validValidatorId(validatorId)
    {
        require(bytes(_validators[validatorId].id).length == 0, "Validator already exists");
        
        // Store normalized validator ID
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        
        _validators[normalizedId] = Validator({
            id: normalizedId,
            status: isEnabled ? ValidatorStatus.Enabled : ValidatorStatus.Disabled,
            totalStaked: 0,
            uniqueStakers: 0
        });
        
        _validatorIds.push(normalizedId);
        
        emit ValidatorAdded(normalizedId, isEnabled);
    }
    
    /**
     * @dev Updates a validator's status
     * @param validatorId The validator identifier
     * @param status The new validator status
     */
    //todo: need to minimize all the custom types from all the func params 
    function updateValidatorStatus(string calldata validatorId, ValidatorStatus status) 
        external 
        override 
        onlyRole(MANAGER_ROLE) 
        validatorExists(validatorId)
    {
        _validators[validatorId].status = status;
        
        emit ValidatorUpdated(validatorId, status);
    }
    
    /**
     * @dev Stakes native XFI to a validator
     * @param validatorId The validator identifier
     */
    function stake(string calldata validatorId) 
        external 
        payable 
        override 
        whenNotPaused 
        nonReentrant 
        validValidatorId(validatorId)
        validatorEnabled(validatorId)
        stakeTimeRestriction(validatorId) 
    {
        (bool isValid, string memory errorMessage) = StakingUtils.validateStakingParams(
            msg.value,
            _minimumStakeAmount
        );
        require(isValid, errorMessage);
        
        require(!_emergencyWithdrawalRequested[msg.sender], "Emergency withdrawal in process");
        
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        
        // Check if this is a new stake to this validator
        bool isNewStake = userStake.amount == 0;
        
        // Update user stake
        userStake.amount += msg.value;
        userStake.stakedAt = block.timestamp;
        
        // Update validator data
        _validators[normalizedId].totalStaked += msg.value;
        if (isNewStake) {
            _validators[normalizedId].uniqueStakers++;
            _userValidators[msg.sender].push(normalizedId);
        }
        
        // Update user total
        _userTotalStaked[msg.sender] += msg.value;
        
        // Convert XFI to MPX for event
        uint256 mpxAmount = PriceConverter.toMPX(_oracle, msg.value);
        
        emit Staked(msg.sender, normalizedId, msg.value, mpxAmount);
    }
    
    /**
     * @dev Initiates unstaking from a validator
     * @param validatorId The validator identifier
     * @param amount The amount to unstake
     */
    function initiateUnstake(string calldata validatorId, uint256 amount) 
        external 
        override 
        nonReentrant 
        validValidatorId(validatorId) 
        validatorExists(validatorId)
        unstakeTimeRestriction(validatorId)
        notInUnstakeProcess(validatorId)
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        
        require(userStake.amount >= amount, "Insufficient staked amount");
        require(amount > 0, "Amount must be greater than zero");
        require(!_emergencyWithdrawalRequested[msg.sender], "Emergency withdrawal in process");
        
        // Mark as in unstake process and record timestamp
        userStake.inUnstakeProcess = true;
        userStake.unstakeInitiatedAt = block.timestamp;
        
        // Automatically initiate reward claim for better UX
        emit RewardClaimInitiated(msg.sender, normalizedId);
        
        // Convert XFI to MPX for event
        uint256 mpxAmount = PriceConverter.toMPX(_oracle, amount);
        
        emit UnstakeInitiated(msg.sender, normalizedId, amount, mpxAmount);
    }
    
    /**
     * @dev Completes an unstake process
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @param amount The amount to unstake
     */
    function completeUnstake(address staker, string calldata validatorId, uint256 amount) 
        external 
        override 
        onlyRole(OPERATOR_ROLE) 
        nonReentrant 
        validValidatorId(validatorId)
        validatorExists(validatorId)
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        UserStake storage userStake = _userStakes[staker][normalizedId];
        
        require(userStake.inUnstakeProcess, "No unstake in process");
        require(userStake.amount >= amount, "Insufficient staked amount");
        
        // Update user stake
        userStake.amount -= amount;
        userStake.inUnstakeProcess = false;
        
        // Update validator data
        _validators[normalizedId].totalStaked -= amount;
        if (userStake.amount == 0) {
            _validators[normalizedId].uniqueStakers--;
            // Remove validator from user's list if no more stake
            _removeValidatorFromUserList(staker, normalizedId);
        }
        
        // Update user total
        _userTotalStaked[staker] -= amount;
        
        // Transfer XFI back to user
        (bool success, ) = staker.call{value: amount}("");
        require(success, "Transfer failed");
        
        // Convert XFI to MPX for event
        uint256 mpxAmount = PriceConverter.toMPX(_oracle, amount);
        
        emit UnstakeCompleted(staker, normalizedId, amount, mpxAmount);
    }
    
    /**
     * @dev Initiates reward claim for a validator
     * @param validatorId The validator identifier
     */
    function initiateRewardClaim(string calldata validatorId) 
        external 
        override 
        nonReentrant 
        validValidatorId(validatorId)
        validatorExists(validatorId)
        claimTimeRestriction(validatorId)
        notInUnstakeProcess(validatorId)
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        
        require(!_emergencyWithdrawalRequested[msg.sender], "Emergency withdrawal in process");
        
        emit RewardClaimInitiated(msg.sender, normalizedId);
    }
    
    /**
     * @dev Completes a reward claim
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @param amount The amount of rewards to claim
     * @param isInitiatedDueUnstake Whether the claim was initiated due to unstake
     */
    function completeRewardClaim(
        address staker, 
        string calldata validatorId, 
        uint256 amount,
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
        require(amount > 0, "Amount must be greater than zero");
        require(msg.value >= amount, "Insufficient rewards");
        
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        UserStake storage userStake = _userStakes[staker][normalizedId];
        require(userStake.amount > 0, "No stake for this validator");
        
        // Allow claim during unstake process only if initiated due to unstake
        if (userStake.inUnstakeProcess) {
            require(isInitiatedDueUnstake, "Unstake in process");
        }
        
        // Transfer rewards to user
        (bool success, ) = staker.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit RewardClaimed(staker, normalizedId, amount);
    }
    
    /**
     * @dev Initiates emergency withdrawal
     */
    function initiateEmergencyWithdrawal() 
        external 
        override 
        nonReentrant
    {
        require(_userTotalStaked[msg.sender] > 0, "No funds to withdraw");
        require(!_emergencyWithdrawalRequested[msg.sender], "Emergency withdrawal already requested");
        
        // Mark as emergency withdrawal requested
        _emergencyWithdrawalRequested[msg.sender] = true;
        
        emit EmergencyWithdrawalInitiated(msg.sender);
    }
    
    /**
     * @dev Completes emergency withdrawal
     * @param staker The address of the staker
     * @param amount The amount to withdraw
     */
    function completeEmergencyWithdrawal(address staker, uint256 amount) 
        external 
        override 
        onlyRole(OPERATOR_ROLE) 
        nonReentrant
    {
        require(_emergencyWithdrawalRequested[staker], "No emergency withdrawal requested");
        require(amount > 0 && amount <= _userTotalStaked[staker], "Invalid amount");
        
        // Reset emergency withdrawal flag
        _emergencyWithdrawalRequested[staker] = false;
        
        // Get list of user validators
        string[] memory userValidators = _userValidators[staker];
        
        // Update validator stats and clear all user stakes
        for (uint256 i = 0; i < userValidators.length; i++) {
            string memory validatorId = userValidators[i];
            UserStake storage userStake = _userStakes[staker][validatorId];
            
            if (userStake.amount > 0) {
                // Update validator stats
                _validators[validatorId].totalStaked -= userStake.amount;
                _validators[validatorId].uniqueStakers--;
                
                // Clear user stake
                userStake.amount = 0;
                userStake.stakedAt = 0;
                userStake.inUnstakeProcess = false;
                userStake.unstakeInitiatedAt = 0;
            }
        }
        
        // Clear user validators and total staked
        delete _userValidators[staker];
        _userTotalStaked[staker] = 0;
        
        // Transfer XFI back to user
        (bool success, ) = staker.call{value: amount}("");
        require(success, "Transfer failed");
        
        // Convert XFI to MPX for event
        uint256 mpxAmount = PriceConverter.toMPX(_oracle, amount);
        
        emit EmergencyWithdrawalCompleted(staker, amount, mpxAmount);
    }
    
    /**
     * @dev Gets validator details
     * @param validatorId The validator identifier
     * @return Validator The validator details
     */
    function getValidator(string calldata validatorId) 
        external 
        view 
        override 
        returns (Validator memory) 
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        return _validators[normalizedId];
    }
    
    /**
     * @dev Gets validator status
     * @param validatorId The validator identifier
     * @return ValidatorStatus The validator status
     */
    function getValidatorStatus(string calldata validatorId) 
        external 
        view 
        override 
        returns (ValidatorStatus) 
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        return _validators[normalizedId].status;
    }
    
    /**
     * @dev Gets the total number of validators
     * @return uint256 The validator count
     */
    function getValidatorCount() 
        external 
        view 
        override 
        returns (uint256) 
    {
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
    function getUserStake(address staker, string calldata validatorId) 
        external 
        view 
        override 
        returns (UserStake memory) 
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        return _userStakes[staker][normalizedId];
    }
    
    /**
     * @dev Gets a user's total staked amount
     * @param staker The address of the staker
     * @return uint256 The total staked amount
     */
    function getUserTotalStaked(address staker) 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _userTotalStaked[staker];
    }
    
    /**
     * @dev Gets all validators a user has staked with
     * @param staker The address of the staker
     * @return string[] Array of validator identifiers
     */
    function getUserValidators(address staker) 
        external 
        view 
        override 
        returns (string[] memory) 
    {
        return _userValidators[staker];
    }
    
    /**
     * @dev Checks if an unstake is in process for a validator
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @return bool Whether unstake is in process
     */
    function isUnstakeInProcess(address staker, string calldata validatorId) 
        external 
        view 
        override 
        returns (bool) 
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        return _userStakes[staker][normalizedId].inUnstakeProcess;
    }
    
    /**
     * @dev Gets the minimum stake amount
     * @return uint256 The minimum stake amount
     */
    function getMinimumStakeAmount() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _minimumStakeAmount;
    }
    
    /**
     * @dev Sets the minimum stake amount
     * @param amount The new minimum stake amount
     */
    function setMinimumStakeAmount(uint256 amount) 
        external 
        override 
        onlyRole(MANAGER_ROLE) 
    {
        _minimumStakeAmount = amount;
    }
    
    /**
     * @dev Pauses staking operations
     */
    function pauseStaking() 
        external 
        override 
        onlyRole(MANAGER_ROLE) 
    {
        _pause();
    }
    
    /**
     * @dev Unpauses staking operations
     */
    function unpauseStaking() 
        external 
        override 
        onlyRole(MANAGER_ROLE) 
    {
        _unpause();
    }
    
    /**
     * @dev Removes a validator from a user's list
     * @param staker The address of the staker
     * @param validatorId The validator identifier to remove
     */
    function _removeValidatorFromUserList(address staker, string memory validatorId) private {
        string[] storage userValidators = _userValidators[staker];
        
        for (uint256 i = 0; i < userValidators.length; i++) {
            if (keccak256(bytes(userValidators[i])) == keccak256(bytes(validatorId))) {
                // Replace with last element and pop
                userValidators[i] = userValidators[userValidators.length - 1];
                userValidators.pop();
                break;
            }
        }
    }
    
    /**
     * @dev Sets the minimum stake interval
     * @param interval The new minimum stake interval in seconds
     */
    function setMinStakeInterval(uint256 interval) 
        external 
        override 
        onlyRole(MANAGER_ROLE) 
    {
        _minStakeInterval = interval;
    }
    
    /**
     * @dev Gets the minimum stake interval
     * @return uint256 The minimum stake interval in seconds
     */
    function getMinStakeInterval() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _minStakeInterval;
    }
    
    /**
     * @dev Sets the minimum unstake interval
     * @param interval The new minimum unstake interval in seconds
     */
    function setMinUnstakeInterval(uint256 interval) 
        external 
        override 
        onlyRole(MANAGER_ROLE) 
    {
        _minUnstakeInterval = interval;
    }
    
    /**
     * @dev Gets the minimum unstake interval
     * @return uint256 The minimum unstake interval in seconds
     */
    function getMinUnstakeInterval() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _minUnstakeInterval;
    }
    
    /**
     * @dev Sets the minimum claim interval
     * @param interval The new minimum claim interval in seconds
     */
    function setMinClaimInterval(uint256 interval) 
        external 
        override 
        onlyRole(MANAGER_ROLE) 
    {
        _minClaimInterval = interval;
    }
    
    /**
     * @dev Gets the minimum claim interval
     * @return uint256 The minimum claim interval in seconds
     */
    function getMinClaimInterval() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _minClaimInterval;
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
        override 
        onlyRole(OPERATOR_ROLE) 
        nonReentrant 
        validValidatorId(validatorId)
        validatorExists(validatorId)
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(validatorId);
        UserStake storage userStake = _userStakes[staker][normalizedId];
        
        // Check if unstake is in process
        require(userStake.inUnstakeProcess, "No unstake in process");
        require(userStake.amount >= unstakeAmount, "Insufficient staked amount");
        
        // Process rewards first if any
        if (rewardAmount > 0) {
            // Transfer rewards to user
            (bool rewardSuccess, ) = staker.call{value: rewardAmount}("");
            require(rewardSuccess, "Reward transfer failed");
            
            emit RewardClaimed(staker, normalizedId, rewardAmount);
        }
        
        // Process unstake
        // Update user stake
        userStake.amount -= unstakeAmount;
        userStake.inUnstakeProcess = false;
        userStake.unstakeInitiatedAt = 0; // Reset timestamp
        
        // Update validator data
        _validators[normalizedId].totalStaked -= unstakeAmount;
        if (userStake.amount == 0) {
            _validators[normalizedId].uniqueStakers--;
            // Remove validator from user's list if no more stake
            _removeValidatorFromUserList(staker, normalizedId);
        }
        
        // Update user total
        _userTotalStaked[staker] -= unstakeAmount;
        
        // Transfer XFI back to user
        (bool unstakeSuccess, ) = staker.call{value: unstakeAmount}("");
        require(unstakeSuccess, "Unstake transfer failed");
        
        // Convert XFI to MPX for event
        uint256 mpxAmount = PriceConverter.toMPX(_oracle, unstakeAmount);
        
        emit UnstakeCompleted(staker, normalizedId, unstakeAmount, mpxAmount);
    }
    
    /**
     * @dev Sets up a validator migration
     * @param oldValidatorId The source validator identifier
     * @param newValidatorId The destination validator identifier
     */
    function setupValidatorMigration(string calldata oldValidatorId, string calldata newValidatorId) 
        external 
        override 
        onlyRole(MANAGER_ROLE)
        validValidatorId(oldValidatorId)
        validValidatorId(newValidatorId)
        validatorExists(oldValidatorId)
        validatorExists(newValidatorId)
    {
        string memory normalizedOldId = StakingUtils.normalizeValidatorId(oldValidatorId);
        string memory normalizedNewId = StakingUtils.normalizeValidatorId(newValidatorId);
        
        // Ensure validators are different
        require(keccak256(bytes(normalizedOldId)) != keccak256(bytes(normalizedNewId)), 
            "Cannot migrate to same validator");
        
        // Update old validator status to deprecated
        _validators[normalizedOldId].status = ValidatorStatus.Deprecated;
        
        emit ValidatorUpdated(normalizedOldId, ValidatorStatus.Deprecated);
    }
    
    /**
     * @dev Migrates a user's stake from a deprecated validator to a new one
     * @param fromValidatorId The identifier of the deprecated validator
     * @param toValidatorId The identifier of the new validator
     */
    function migrateStake(string calldata fromValidatorId, string calldata toValidatorId) 
        external 
        override 
        nonReentrant 
        validValidatorId(fromValidatorId)
        validValidatorId(toValidatorId)
        validatorExists(fromValidatorId)
        validatorEnabled(toValidatorId)
        notInUnstakeProcess(fromValidatorId)
    {
        string memory normalizedFromId = StakingUtils.normalizeValidatorId(fromValidatorId);
        string memory normalizedToId = StakingUtils.normalizeValidatorId(toValidatorId);
        
        // Check that from validator is deprecated
        require(
            _validators[normalizedFromId].status == ValidatorStatus.Deprecated,
            "Source validator must be deprecated"
        );
        
        // Check that target validator is enabled
        require(
            _validators[normalizedToId].status == ValidatorStatus.Enabled,
            "Target validator must be enabled"
        );
        
        // Get user's stake in the old validator
        UserStake storage oldStake = _userStakes[msg.sender][normalizedFromId];
        require(oldStake.amount > 0, "No stake to migrate");
        require(!oldStake.inUnstakeProcess, "Unstake in process");
        
        // Check time restriction - if we are migrating from deprecated, no time restriction
        // But let's apply a small safety check to prevent same-block attacks
        require(
            block.timestamp > oldStake.stakedAt,
            "Cannot migrate in the same block as staking"
        );
        
        // Get or initialize stake in the new validator
        UserStake storage newStake = _userStakes[msg.sender][normalizedToId];
        bool isNewStake = newStake.amount == 0;
        
        // Keep track of migrated amount
        uint256 migrationAmount = oldStake.amount;
        
        // Update stakes
        newStake.amount += migrationAmount;
        newStake.stakedAt = block.timestamp; // Reset staking time
        
        // Update validator stats
        _validators[normalizedToId].totalStaked += migrationAmount;
        if (isNewStake) {
            _validators[normalizedToId].uniqueStakers++;
            _userValidators[msg.sender].push(normalizedToId);
        }
        
        // Update old validator stats
        _validators[normalizedFromId].totalStaked -= migrationAmount;
        _validators[normalizedFromId].uniqueStakers--;
        
        // Remove old validator from user list as stake is now zero
        _removeValidatorFromUserList(msg.sender, normalizedFromId);
        
        // Reset old stake
        oldStake.amount = 0;
        oldStake.stakedAt = 0;
        oldStake.inUnstakeProcess = false;
        oldStake.unstakeInitiatedAt = 0;
        
        // Convert XFI to MPX for event
        uint256 mpxAmount = PriceConverter.toMPX(_oracle, migrationAmount);
        
        emit StakeMigrated(msg.sender, normalizedFromId, normalizedToId, migrationAmount, mpxAmount);
    }
    
    /**
     * @dev Sets the Oracle address
     * @param oracleAddress Address of the oracle contract
     */
    function setOracle(address oracleAddress) 
        external 
        override 
        onlyRole(MANAGER_ROLE) 
    {
        require(oracleAddress != address(0), "Invalid oracle address");
        _oracle = IOracle(oracleAddress);
    }
    
    /**
     * @dev Gets the oracle address
     * @return Address of the oracle contract
     */
    function getOracle() 
        external 
        view 
        override
        returns (address) 
    {
        return address(_oracle);
    }
    
    /**
     * @dev Checks if emergency withdrawal was requested
     * @param staker The address of the staker
     * @return bool Whether emergency withdrawal was requested
     */
    function isEmergencyWithdrawalRequested(address staker)
        external
        view
        returns (bool)
    {
        return _emergencyWithdrawalRequested[staker];
    }
    
    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {
        // Only accept ETH from transactions
    }
} 