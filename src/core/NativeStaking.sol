// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/INativeStaking.sol";
import "../libraries/StakingUtils.sol";

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
    
    // Validator mappings
    mapping(string => Validator) private _validators;
    string[] private _validatorIds;
    
    // User stake mappings
    mapping(address user => mapping(string validatorId => UserStake)) private _userStakes;
    mapping(address user => string[] validators) private _userValidators;
    mapping(address user => uint256 totalStaked) private _userTotalStaked;
    mapping(address user => bool emergencyWithdrawalRequested) private _emergencyWithdrawalRequested;
    
    // Contract settings
    uint256 private _minimumStakeAmount;
    
    /**
     * @dev Initializes the contract
     * @param admin Address of the admin who will have DEFAULT_ADMIN_ROLE
     * @param minimumStakeAmount The minimum amount required for staking
     */
    function initialize(
        address admin,
        uint256 minimumStakeAmount
    ) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
        
        _minimumStakeAmount = minimumStakeAmount;
    }
    
    /**
     * @dev Modifier to check if validator exists and is enabled
     */
    modifier validatorEnabled(string calldata validatorId) {
        require(_validators[validatorId].status == ValidatorStatus.Enabled, "Validator is not enabled");
        _;
    }
    
    /**
     * @dev Modifier to check if validator exists
     */
    modifier validatorExists(string calldata validatorId) {
        require(bytes(_validators[validatorId].id).length > 0, "Validator does not exist");
        _;
    }

    /**
     * @dev Adds a new validator
     * @param validatorId The validator identifier
     * @param status The initial validator status
     */
    function addValidator(string calldata validatorId, ValidatorStatus status) 
        external 
        override 
        onlyRole(MANAGER_ROLE) 
    {
        //todo: need to check if validator starts with "mxvaloper" and len and case 
        //! some more checks if this is ral validatroe 
        //! extract al the validator chacks into separate modidier 
        require(StakingUtils.validateValidatorId(validatorId), "Invalid validator ID format");
        require(bytes(_validators[validatorId].id).length == 0, "Validator already exists");
        
        _validators[validatorId] = Validator({
            id: validatorId,
            status: status,
            totalStaked: 0,
            uniqueStakers: 0
        });
        
        _validatorIds.push(validatorId);
        
        emit ValidatorAdded(validatorId, status);
    }
    
    /**
     * @dev Updates a validator's status
     * @param validatorId The validator identifier
     * @param status The new validator status
     */
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
        validatorEnabled(validatorId) 
    {
        //todo: check ifthere any delays between stakes etc. 


        require(msg.value >= _minimumStakeAmount, "Stake amount below minimum");
        require(!_emergencyWithdrawalRequested[msg.sender], "Emergency withdrawal in process");
        
        UserStake storage userStake = _userStakes[msg.sender][validatorId];
        
        // Check if this is a new stake to this validator
        bool isNewStake = userStake.amount == 0;
        
        // Update user stake
        userStake.amount += msg.value;
        userStake.stakedAt = block.timestamp;
        
        // Update validator data
        _validators[validatorId].totalStaked += msg.value;
        if (isNewStake) {
            _validators[validatorId].uniqueStakers++;
            _userValidators[msg.sender].push(validatorId);
        }
        
        // Update user total
        _userTotalStaked[msg.sender] += msg.value;
        
        emit Staked(msg.sender, validatorId, msg.value);
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
        validatorExists(validatorId)
    {
        UserStake storage userStake = _userStakes[msg.sender][validatorId];
        
        require(userStake.amount >= amount, "Insufficient staked amount");
        require(amount > 0, "Amount must be greater than zero");
        require(!userStake.inUnstakeProcess, "Unstake already in process");
        require(!_emergencyWithdrawalRequested[msg.sender], "Emergency withdrawal in process");
        
        // Mark as in unstake process
        userStake.inUnstakeProcess = true;
        
        emit UnstakeInitiated(msg.sender, validatorId, amount);
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
        validatorExists(validatorId)
    {
        //! if claim happens if user unstakes? 
        //! Do we consider flow: User Unstakes -> Unstake inits -> Backend finishes unstake 
        //!                                    -> Claim inits ->  Backend finishes claim
        //!                                       
        //!   so if user call initClaim happens only claim                                  
        //!                              initClaim -> Backend Fulfils Calim       

        //todo: this flow may require additional flag in completeClaim function "isInintedDueUnstake"

        UserStake storage userStake = _userStakes[staker][validatorId];
        
        require(userStake.inUnstakeProcess, "No unstake in process");
        require(userStake.amount >= amount, "Insufficient staked amount");
        
        // Update user stake
        userStake.amount -= amount;
        userStake.inUnstakeProcess = false;
        
        // Update validator data
        _validators[validatorId].totalStaked -= amount;
        if (userStake.amount == 0) {
            _validators[validatorId].uniqueStakers--;
            // Remove validator from user's list if no more stake
            _removeValidatorFromUserList(staker, validatorId);
        }
        
        // Update user total
        _userTotalStaked[staker] -= amount;
        
        // Transfer XFI back to user
        (bool success, ) = staker.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit UnstakeCompleted(staker, validatorId, amount);
    }
    
    /**
     * @dev Initiates reward claim for a validator
     * @param validatorId The validator identifier
     */
    function initiateRewardClaim(string calldata validatorId) 
        external 
        override 
        nonReentrant 
        validatorExists(validatorId)
    {
        UserStake storage userStake = _userStakes[msg.sender][validatorId];
        
        require(userStake.amount > 0, "No stake for this validator");
        require(!userStake.inUnstakeProcess, "Unstake in process");
        require(!_emergencyWithdrawalRequested[msg.sender], "Emergency withdrawal in process");
        
        emit RewardClaimInitiated(msg.sender, validatorId);
    }
    
    /**
     * @dev Completes a reward claim
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @param amount The amount of rewards to claim
     */
    function completeRewardClaim(address staker, string calldata validatorId, uint256 amount) 
        external 
        override 
        onlyRole(OPERATOR_ROLE) 
        nonReentrant 
        validatorExists(validatorId)
    {
        require(amount > 0, "Amount must be greater than zero");
        
        UserStake storage userStake = _userStakes[staker][validatorId];
        require(userStake.amount > 0, "No stake for this validator");
        require(!userStake.inUnstakeProcess, "Unstake in process");
        
        // Transfer rewards to user
        (bool success, ) = staker.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit RewardClaimed(staker, validatorId, amount);
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
        
        // Transfer XFI back to user
        (bool success, ) = staker.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit EmergencyWithdrawalCompleted(staker, amount);
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
        return _validators[validatorId];
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
        return _validators[validatorId].status;
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
        return _userStakes[staker][validatorId];
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
        return _userStakes[staker][validatorId].inUnstakeProcess;
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
     * @dev Fallback function to receive ETH
     */
    receive() external payable {
        // Only accept ETH from transactions
    }
} 