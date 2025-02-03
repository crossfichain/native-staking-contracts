// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface INativeStaking {
    /// @notice Represents staking position details
    struct StakingPosition {
        uint256 lockedAmount;
        uint256 collateralAmount;
        uint256 shares;
        uint256 pendingRewards;
        uint256 lastRewardTimestamp;
    }

    /// @notice Emitted when user stakes native tokens
    event Staked(address indexed user, uint256 nativeAmount, uint256 collateralAmount);
    
    /// @notice Emitted when rewards are distributed
    event RewardsDistributed(uint256 totalRewards, uint256 newCollateralMinted);
    
    /// @notice Emitted when user unstakes
    event Unstaked(address indexed user, uint256 nativeAmount, uint256 rewardsAmount);
    
    /// @notice Emitted when validator is slashed
    event ValidatorSlashed(uint256 slashAmount, uint256 timestamp);
    
    /// @notice Emitted when rewards are compounded
    event RewardsCompounded(uint256 totalNativeRewards, uint256 newCollateralAmount);

    function stake() external payable;
    function unstake(uint256 amount) external;
    // function compoundRewards() external;
    function handleSlashing(uint256 slashAmount) external;
    
    function getStakingPosition(address user) external view returns (
        uint256 lockedAmount,
        uint256 collateralAmount,
        uint256 shares,
        uint256 pendingRewards
    );

    function getCurrentConversionRate() external view returns (uint256);
}