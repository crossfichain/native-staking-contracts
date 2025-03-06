// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title INativeStakingManager
 * @dev Interface for the Native Staking Manager contract that routes staking operations
 * to the appropriate staking contract (APR or APY)
 * Validator information is now only passed to events for off-chain processing
 */
interface INativeStakingManager {
    /**
     * @dev Stakes XFI using the APR model
     * @param amount The amount of XFI to stake
     * @param validator The validator address/ID (only for events, not stored on-chain)
     * @return success Boolean indicating if the stake was successful
     */
    function stakeAPR(uint256 amount, string calldata validator) external payable returns (bool success);
    
    /**
     * @dev Stakes XFI using the APY model (compound vault)
     * @param amount The amount of XFI to stake
     * @return shares The amount of vault shares received
     */
    function stakeAPY(uint256 amount) external payable returns (uint256 shares);
    
    /**
     * @dev Requests to unstake XFI from the APR model
     * @param amount The amount of XFI to unstake
     * @param validator The validator address/ID (only for events, not stored on-chain)
     * @return requestId The ID of the unstake request
     */
    function unstakeAPR(uint256 amount, string calldata validator) external returns (uint256 requestId);
    
    /**
     * @dev Claims XFI from a completed APR unstake request
     * @param requestId The ID of the unstake request to claim
     * @return amount The amount of XFI claimed
     */
    function claimUnstakeAPR(uint256 requestId) external returns (uint256 amount);
    
    /**
     * @dev Withdraws XFI from the APY model by burning vault shares
     * If there are sufficient liquid assets, withdrawal is immediate
     * Otherwise, it will be queued for the unbonding period
     * @param shares The amount of vault shares to burn
     * @return assets The amount of XFI withdrawn or 0 if request is queued
     */
    function withdrawAPY(uint256 shares) external returns (uint256 assets);
    
    /**
     * @dev Claims XFI from a completed APY withdrawal request
     * @param requestId The ID of the withdrawal request to claim
     * @return assets The amount of XFI claimed
     */
    function claimWithdrawalAPY(uint256 requestId) external returns (uint256 assets);
    
    /**
     * @dev Claims rewards from the APR model
     * @return amount The amount of rewards claimed
     */
    function claimRewardsAPR() external returns (uint256 amount);
    
    /**
     * @dev Gets the address of the APR staking contract
     * @return The address of the APR staking contract
     */
    function getAPRContract() external view returns (address);
    
    /**
     * @dev Gets the address of the APY staking contract
     * @return The address of the APY staking contract
     */
    function getAPYContract() external view returns (address);
    
    /**
     * @dev Gets the address of the XFI token (or WXFI if wrapped)
     * @return The address of the XFI token
     */
    function getXFIToken() external view returns (address);
    
    /**
     * @dev Gets the current unbonding period in seconds
     * @return The unbonding period in seconds
     */
    function getUnbondingPeriod() external view returns (uint256);
    
    /**
     * @dev Checks if unstaking is frozen (during the initial freeze period after launch)
     * @return True if unstaking is still frozen
     */
    function isUnstakingFrozen() external view returns (bool);
    
    /**
     * @dev Gets the unstaking freeze time in seconds
     * @return The unstaking freeze time in seconds
     */
    function getUnstakeFreezeTime() external view returns (uint256);
    
    /**
     * @dev Gets the launch timestamp
     * @return The launch timestamp
     */
    function getLaunchTimestamp() external view returns (uint256);
} 