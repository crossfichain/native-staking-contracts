// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title INativeStaking
 * @dev Interface for the NativeStaking contract
 */
interface INativeStaking {
    /**
     * @dev Validator status enum
     */
    enum ValidatorStatus {
        Disabled,
        Enabled,
        Deprecated   // For validators that are being phased out
    }

    /**
     * @dev Validator data struct
     */
    struct Validator {
        string id;
        ValidatorStatus status;
        uint256 totalStaked;
        uint256 uniqueStakers;
    }

    /**
     * @dev User stake data struct
     */
    struct UserStake {
        uint256 amount;
        uint256 mpxAmount;
        uint256 stakedAt;
        bool inUnstakeProcess;
        uint256 unstakeInitiatedAt; // Timestamp when unstake was initiated
        uint256 unstakeAmount;      // Amount requested for unstake
    }

    // Events
    event ValidatorAdded(string validatorId, bool isEnabled);
    event ValidatorStatusUpdated(string validatorId, ValidatorStatus status);
    
    event Staked(address indexed staker, string validatorId, uint256 amount, uint256 mpxAmount);
    event UnstakeInitiated(address indexed staker, string validatorId, uint256 amount, uint256 mpxAmount);
    event UnstakeCompleted(address indexed staker, string validatorId, uint256 amount, uint256 mpxAmount);
    
    event RewardClaimInitiated(address indexed staker, string validatorId);
    event RewardClaimed(address indexed staker, string validatorId, uint256 amount);
    
    event EmergencyWithdrawalInitiated(address indexed staker);
    event EmergencyWithdrawalCompleted(address indexed staker, uint256 amount, uint256 mpxAmount);
    
    event StakeMigrated(address indexed staker, string fromValidatorId, string toValidatorId, uint256 amount, uint256 mpxAmount);

    // Validator management functions
    function setValidatorStatus(string calldata validatorId, ValidatorStatus status) external;
    function getValidator(string calldata validatorId) external view returns (Validator memory);
    function getValidatorStatus(string calldata validatorId) external view returns (ValidatorStatus);
    function getValidatorCount() external view returns (uint256);
    function getValidators() external view returns (Validator[] memory);

    // User staking functions
    function stake(string calldata validatorId) external payable;
    
    /**
     * @dev Initiates unstaking of the full amount from a validator
     * @param validatorId The validator identifier
     */
    function initiateUnstake(string calldata validatorId) external;
    
    // Previous version with partial unstaking
    // function initiateUnstake(string calldata validatorId, uint256 amount) external;
    
    function completeUnstake(address staker, string calldata validatorId, uint256 amount) external;
    
    // Reward claiming functions
    function initiateRewardClaim(string calldata validatorId) external;
    function completeRewardClaim(address staker, string calldata validatorId, bool isInitiatedDueUnstake) external payable;
    
    // Combined processing function
    function processRewardAndUnstake(address staker, string calldata validatorId, uint256 unstakeAmount, uint256 rewardAmount) external payable;
    
    // Emergency functions
    function initiateEmergencyWithdrawal() external;
    function completeEmergencyWithdrawal(address staker, uint256 amount) external;
    function isEmergencyWithdrawalRequested(address staker) external view returns (bool);
    
    // View functions
    function getUserStake(address staker, string calldata validatorId) external view returns (UserStake memory);
    function getUserTotalStaked(address staker) external view returns (uint256);
    function getUserValidators(address staker) external view returns (string[] memory);
    function isUnstakeInProcess(address staker, string calldata validatorId) external view returns (bool);
    
    /**
     * @dev Gets the unstake status and amount for a given validator
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @return inProcess Whether unstake is in process
     * @return amount The amount requested for unstake
     */
    function getUnstakeStatus(address staker, string calldata validatorId) external view returns (bool inProcess, uint256 amount);
    
    // Protocol settings
    function getMinimumStakeAmount() external view returns (uint256);
    function setMinimumStakeAmount(uint256 amount) external;
    function pauseStaking() external;
    function unpauseStaking() external;

    // Time interval management functions
    function setMinStakeInterval(uint256 interval) external;
    function getMinStakeInterval() external view returns (uint256);
    function setMinUnstakeInterval(uint256 interval) external;
    function getMinUnstakeInterval() external view returns (uint256);
    function setMinClaimInterval(uint256 interval) external;
    function getMinClaimInterval() external view returns (uint256);

    // Validator migration functions
    function setupValidatorMigration(string calldata oldValidatorId, string calldata newValidatorId) external;
    function migrateStake(string calldata fromValidatorId, string calldata toValidatorId) external;
    
    // Oracle functions
    function setOracle(address oracleAddress) external;
    function getOracle() external view returns (address);
} 