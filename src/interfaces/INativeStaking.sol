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
        Enabled
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
        uint256 stakedAt;
        bool inUnstakeProcess;
    }

    // Events
    event ValidatorAdded(string indexed validatorId, ValidatorStatus status);
    event ValidatorUpdated(string indexed validatorId, ValidatorStatus status);
    
    event Staked(address indexed staker, string indexed validatorId, uint256 amount);
    event UnstakeInitiated(address indexed staker, string indexed validatorId, uint256 amount);
    event UnstakeCompleted(address indexed staker, string indexed validatorId, uint256 amount);
    
    event RewardClaimInitiated(address indexed staker, string indexed validatorId);
    event RewardClaimed(address indexed staker, string indexed validatorId, uint256 amount);
    
    event EmergencyWithdrawalInitiated(address indexed staker);
    event EmergencyWithdrawalCompleted(address indexed staker, uint256 amount);

    // Validator management functions
    function addValidator(string calldata validatorId, ValidatorStatus status) external;
    function updateValidatorStatus(string calldata validatorId, ValidatorStatus status) external;
    function getValidator(string calldata validatorId) external view returns (Validator memory);
    function getValidatorStatus(string calldata validatorId) external view returns (ValidatorStatus);
    function getValidatorCount() external view returns (uint256);
    function getValidators() external view returns (Validator[] memory);

    // User staking functions
    function stake(string calldata validatorId) external payable;
    function initiateUnstake(string calldata validatorId, uint256 amount) external;
    function completeUnstake(address staker, string calldata validatorId, uint256 amount) external;
    
    // Reward claiming functions
    function initiateRewardClaim(string calldata validatorId) external;
    function completeRewardClaim(address staker, string calldata validatorId, uint256 amount) external;
    
    // Emergency functions
    function initiateEmergencyWithdrawal() external;
    function completeEmergencyWithdrawal(address staker, uint256 amount) external;
    
    // View functions
    function getUserStake(address staker, string calldata validatorId) external view returns (UserStake memory);
    function getUserTotalStaked(address staker) external view returns (uint256);
    function getUserValidators(address staker) external view returns (string[] memory);
    function isUnstakeInProcess(address staker, string calldata validatorId) external view returns (bool);
    
    // Protocol settings
    function getMinimumStakeAmount() external view returns (uint256);
    function setMinimumStakeAmount(uint256 amount) external;
    function pauseStaking() external;
    function unpauseStaking() external;
} 