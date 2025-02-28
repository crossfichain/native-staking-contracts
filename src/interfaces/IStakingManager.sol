// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStakingManager
 * @notice Interface for the central staking manager that handles both flow types
 * @dev Acts as a gateway for users and administrators to interact with the staking system
 */
interface IStakingManager {
    // ============ Type Definitions ============

    /// @notice Enum to define staking flow type
    enum StakingFlow {
        AGGREGATED,    // First flow: Backend aggregates all XFI
        INDIVIDUAL     // Second flow: Individual positions for each user
    }

    /// @notice Structure for validator metadata
    struct ValidatorInfo {
        address evmAddress;          // Address on EVM chain
        string cosmosAddress;        // Validator address on Cosmos
        string name;                 // Human-readable name
        uint256 commission;          // Commission rate in basis points (100 = 1%)
        bool isActive;               // Whether validator is active
    }

    /// @notice Structure for user staking position
    struct StakingPosition {
        uint256 stakedAmount;        // Total staked amount
        uint256 sharesAmount;        // User's share of the pool
        uint256 lastRewardClaim;     // Last reward claim timestamp
        StakingFlow flowType;        // Which flow this position uses
        address[] validators;        // List of validators (for INDIVIDUAL flow)
        mapping(address => uint256) validatorAllocations; // Allocation per validator
    }

    // ============ Events ============

    // === System and Admin Events ===
    event SystemFlowUpdated(StakingFlow newDefaultFlow);
    event MinimumStakeUpdated(uint256 newMinimumStake);
    event RewardRateUpdated(uint256 newDailyRate);
    event FeeRateUpdated(uint256 newFeeRate);

    // === Validator Management Events ===
    event ValidatorRegistered(address indexed validatorAddress, string cosmosAddress, string name);
    event ValidatorUpdated(address indexed validatorAddress, string newCosmosAddress, string newName);
    event ValidatorActivated(address indexed validatorAddress);
    event ValidatorDeactivated(address indexed validatorAddress);
    event ValidatorCommissionUpdated(address indexed validatorAddress, uint256 newCommission);

    // === Aggregated Flow Events ===
    event AggregatedStake(address indexed user, uint256 amount, uint256 shares);
    event AggregatedUnstake(address indexed user, uint256 amount, uint256 shares, uint256 rewards);
    event AggregatedRewardsCompounded(uint256 totalAmount, uint256 newSharePrice);
    event AggregatedRewardsClaimed(address indexed user, uint256 amount);

    // === Individual Flow Events ===
    event IndividualStake(address indexed user, address indexed validator, uint256 amount, uint256 shares);
    event IndividualUnstake(address indexed user, address indexed validator, uint256 amount, uint256 shares, uint256 rewards);
    event IndividualRewardsUpdated(address indexed validator, uint256 totalAmount);
    event IndividualRewardsClaimed(address indexed user, address indexed validator, uint256 amount);

    // === User Events ===
    event UserFlowChanged(address indexed user, StakingFlow oldFlow, StakingFlow newFlow);
    event UserReinvested(address indexed user, uint256 rewardAmount, uint256 newShares);

    // ============ Admin Functions ============
    
    /// @notice Set the default flow type for new users
    /// @param newFlow The new default flow type
    function setDefaultFlow(StakingFlow newFlow) external;
    
    /// @notice Update minimum stake amount
    /// @param newMinimumStake The new minimum stake in native tokens
    function setMinimumStake(uint256 newMinimumStake) external;
    
    /// @notice Register a new validator
    /// @param validatorAddress EVM address of the validator
    /// @param cosmosAddress Cosmos address of the validator
    /// @param name Human-readable name of the validator
    /// @param commission Commission rate in basis points (100 = 1%)
    function registerValidator(
        address validatorAddress, 
        string calldata cosmosAddress, 
        string calldata name,
        uint256 commission
    ) external;
    
    /// @notice Update validator information
    /// @param validatorAddress Validator address to update
    /// @param cosmosAddress New cosmos address
    /// @param name New validator name
    function updateValidator(
        address validatorAddress,
        string calldata cosmosAddress,
        string calldata name
    ) external;
    
    /// @notice Set validator active status
    /// @param validatorAddress Validator address to update
    /// @param isActive New active status
    function setValidatorStatus(address validatorAddress, bool isActive) external;
    
    /// @notice Update validator commission rate
    /// @param validatorAddress Validator address to update
    /// @param commission New commission rate in basis points
    function setValidatorCommission(address validatorAddress, uint256 commission) external;

    // ============ Operator Functions ============
    
    /// @notice Compound rewards for all users in the aggregated flow
    /// @param rewardAmount Amount of rewards to distribute
    function compoundAggregatedRewards(uint256 rewardAmount) external payable;
    
    /// @notice Update rewards for a specific validator in the individual flow
    /// @param validatorAddress Validator address to update rewards for
    /// @param rewardAmount Amount of rewards to add
    function updateValidatorRewards(address validatorAddress, uint256 rewardAmount) external payable;
    
    /// @notice Emergency pause staking
    function pause() external;
    
    /// @notice Resume staking
    function unpause() external;

    // ============ User Functions ============
    
    /// @notice Stake tokens with specified validator
    /// @param validatorAddress Validator to stake with (use zero address for auto-selection)
    function stake(address validatorAddress) external payable;
    
    /// @notice Unstake tokens from specified validator
    /// @param amount Amount to unstake
    /// @param validatorAddress Validator to unstake from (use zero address for proportional unstake)
    function unstake(uint256 amount, address validatorAddress) external;
    
    /// @notice Claim pending rewards
    /// @param validatorAddress Validator to claim from (use zero address for all validators)
    /// @return Amount of rewards claimed
    function claimRewards(address validatorAddress) external returns (uint256);
    
    /// @notice Claim and reinvest pending rewards
    /// @param validatorAddress Validator to claim from (use zero address for all validators)
    /// @return Amount of rewards reinvested
    function claimAndReinvest(address validatorAddress) external returns (uint256);
    
    /// @notice Change user's flow type
    /// @param newFlow New flow type for the user
    function changeUserFlow(StakingFlow newFlow) external;

    // ============ View Functions ============
    
    /// @notice Get validator information
    /// @param validatorAddress Validator address to query
    /// @return Validator information
    function getValidatorInfo(address validatorAddress) external view returns (ValidatorInfo memory);
    
    /// @notice Get user's staking details
    /// @param user Address of the user
    /// @return stakedAmount Total staked amount
    /// @return sharesAmount Total shares owned
    /// @return pendingRewards Pending rewards
    /// @return flowType Current flow type
    function getUserStaking(address user) external view returns (
        uint256 stakedAmount,
        uint256 sharesAmount,
        uint256 pendingRewards,
        StakingFlow flowType
    );
    
    /// @notice Get user's validator allocations (for INDIVIDUAL flow)
    /// @param user Address of the user
    /// @return validators Array of validator addresses
    /// @return allocations Array of corresponding allocations
    function getUserValidators(address user) external view returns (
        address[] memory validators,
        uint256[] memory allocations
    );
    
    /// @notice Get system statistics
    /// @return totalStaked Total staked across all flows
    /// @return totalUsers Total number of users
    /// @return aggregatedUsers Users in aggregated flow
    /// @return individualUsers Users in individual flow
    /// @return activeValidators Number of active validators
    function getSystemStats() external view returns (
        uint256 totalStaked,
        uint256 totalUsers,
        uint256 aggregatedUsers,
        uint256 individualUsers,
        uint256 activeValidators
    );
    
    /// @notice Get current flow type
    /// @return Current default flow type
    function getDefaultFlow() external view returns (StakingFlow);
    
    /// @notice Get current APR (Annual Percentage Rate)
    /// @return Current APR in basis points (10000 = 100%)
    function getCurrentAPR() external view returns (uint256);
    
    /// @notice Get all active validators
    /// @return Array of active validator addresses
    function getActiveValidators() external view returns (address[] memory);
} 