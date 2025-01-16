// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

interface INativeStaking {
    /// @notice Emitted when user stakes XFI
    event Staked(address indexed user, uint256 xfiAmount, uint256 mpxAmount);
    
    /// @notice Emitted when rewards are distributed
    event RewardsDistributed(uint256 totalRewards, uint256 mpxMinted);
    
    /// @notice Emitted when user unstakes
    event Unstaked(address indexed user, uint256 xfiAmount, uint256 rewardsAmount);
    
    /// @notice Emitted when validator is slashed
    event ValidatorSlashed(uint256 slashAmount, uint256 timestamp);
    
    /// @notice Emitted when rewards are compounded
    event RewardsCompounded(uint256 totalXfiRewards, uint256 newMpxAmount);

    /// @notice Represents staking position details
    struct StakingPosition {
        uint256 stakedAmount;      // Amount of native tokens staked
        uint256 collateralShares;  // Shares of collateral token
        uint256 lastRewardTimestamp;
    }

    /**
     * @notice Stakes XFI tokens and mints equivalent MPX based on oracle price
     * @dev Requires oracle integration for XFI price
     */
    function stake() external payable;

    /**
     * @notice Unstakes XFI tokens and claims rewards
     * @param amount Amount of XFI to unstake
     */
    function unstake(uint256 amount) external;

    /**
     * @notice Compounds rewards by converting XFI rewards to MPX
     * @dev Only callable by authorized backend
     */
    function compoundRewards() external;

    /**
     * @notice Handles validator slashing event
     * @dev Only callable by authorized backend
     * @param slashAmount Amount that was slashed
     */
    function handleSlashing(uint256 slashAmount) external;

    /**
     * @notice Returns user's staking position
     * @param user Address of the user
     */
   function getStakingPosition(address user) external view returns (
        uint256 stakedAmount,
        uint256 collateralShares,
        uint256 pendingRewards
    );

    /**
     * @notice Returns current conversion rate from XFI to MPX
     */
    function getCurrentConversionRate() external view returns (uint256);
}