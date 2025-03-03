// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStakingCore
 * @notice Interface for the StakingCore contract
 * @dev Defines the main staking functionality
 */
interface IStakingCore {
    // ============ Structs ============
    
    /// @notice Validator information
    struct Validator {
        address evmAddress;        // Validator address on EVM
        string cosmosAddress;      // Validator address on Cosmos
        string name;               // Human readable name
        uint256 commission;        // Commission rate in basis points
        uint256 totalStaked;       // Total tokens staked with this validator
        uint256 totalShares;       // Total shares for this validator
        uint256 rewardPool;        // Accumulated rewards for this validator
        uint256 lastUpdateTime;    // Last time rewards were updated
        bool isActive;             // Whether validator is active
    }
    
    /// @notice User staking position
    struct Position {
        uint256 totalStaked;       // Total staked by user
        uint256 totalShares;       // Total shares owned by user
        uint256 lastClaimTime;     // Last time rewards were claimed
        address[] validators;      // Validators user has staked with
        bool isActive;             // Whether position is active
    }
    
    /// @notice User-validator relationship
    struct UserValidatorStake {
        uint256 shares;            // Shares in this validator
        uint256 stakedAmount;      // Amount staked with this validator
        bool isActive;             // Whether stake is active
    }
    
    // ============ Events ============
    
    // System events
    event MinimumStakeUpdated(uint256 newMinimumStake);
    
    // Validator events
    event ValidatorRegistered(address indexed validatorAddress, string cosmosAddress, string name);
    event ValidatorUpdated(address indexed validatorAddress, string newCosmosAddress, string newName);
    event ValidatorActivated(address indexed validatorAddress);
    event ValidatorDeactivated(address indexed validatorAddress);
    event ValidatorCommissionUpdated(address indexed validatorAddress, uint256 newCommission);
    event ValidatorRewardsUpdated(address indexed validatorAddress, uint256 totalAmount);
    
    // User events
    event Staked(address indexed user, address indexed validator, uint256 amount, uint256 shares);
    event Unstaked(address indexed user, address indexed validator, uint256 amount, uint256 shares, uint256 rewards);
    event RewardsClaimed(address indexed user, address indexed validator, uint256 amount);
    event UserAdded(address indexed user);
    event UserRemoved(address indexed user);
    event RewardsReinvested(address indexed user, uint256 amount, uint256 shares);
    
    // ============ Admin Functions ============
    
    function setMinimumStake(uint256 newMinimumStake) external;
    
    function registerValidator(
        address validatorAddress,
        string calldata cosmosAddress,
        string calldata name,
        uint256 commission
    ) external;
    
    function updateValidator(
        address validatorAddress,
        string calldata cosmosAddress,
        string calldata name
    ) external;
    
    function setValidatorStatus(
        address validatorAddress,
        bool isActive
    ) external;
    
    function setValidatorCommission(
        address validatorAddress,
        uint256 commission
    ) external;
    
    // ============ Operator Functions ============
    
    function updateValidatorRewards(
        address validatorAddress,
        uint256 rewardAmount
    ) external payable;
    
    function pause() external;
    
    function unpause() external;
    
    // ============ User Functions ============
    
    function stake(address validatorAddress) external payable;
    
    function unstake(
        uint256 amount,
        address validatorAddress
    ) external;
    
    function claimRewards(address validatorAddress) external returns (uint256);
    
    function claimAndReinvest(address validatorAddress) external returns (uint256);
    
    // ============ View Functions ============
    
    function getValidatorInfo(
        address validatorAddress
    ) external view returns (
        address evmAddress,
        string memory cosmosAddress,
        string memory name,
        uint256 commission,
        uint256 totalStaked,
        uint256 totalShares,
        uint256 rewardPool,
        uint256 lastUpdateTime,
        bool isActive
    );
    
    function getUserPosition(
        address user
    ) external view returns (
        uint256 totalStaked,
        uint256 totalShares,
        uint256 pendingRewards,
        uint256 validatorCount
    );
    
    function getUserValidators(
        address user
    ) external view returns (
        address[] memory validators,
        uint256[] memory stakedAmounts,
        uint256[] memory shares,
        uint256[] memory rewards
    );
    
    function getActiveValidators() external view returns (address[] memory);
    
    function getCurrentAPR() external view returns (uint256);
} 