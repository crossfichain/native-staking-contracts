// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title INativeStakingVault
 * @dev Interface for the Native Staking Vault contract that handles compounding staking (APY model)
 * Extends the ERC-4626 standard for tokenized vaults
 */
interface INativeStakingVault is IERC4626 {
    /**
     * @dev Struct to track a withdrawal request in progress
     * @param assets The amount of assets requested to withdraw
     * @param shares The amount of shares burned for this withdrawal
     * @param unlockTime The timestamp when assets can be claimed
     * @param owner The owner of the withdrawal request
     * @param completed Whether the withdrawal has been completed
     */
    struct WithdrawalRequest {
        uint256 assets;
        uint256 shares;
        uint256 unlockTime;
        address owner;
        bool completed;
    }
    
    /**
     * @dev Requests a withdrawal, handling the unbonding period if needed
     * Called when there are not enough liquid assets in the vault
     * @param assets The amount of underlying assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return requestId The ID of the withdrawal request
     */
    function requestWithdrawal(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 requestId);
    
    /**
     * @dev Claims assets from a completed withdrawal request
     * @param requestId The ID of the withdrawal request
     * @return assets The amount of assets claimed
     */
    function claimWithdrawal(uint256 requestId) external returns (uint256 assets);
    
    /**
     * @dev Gets all pending withdrawal requests for a user
     * @param user The user to get withdrawal requests for
     * @return An array of WithdrawalRequest structs
     */
    function getUserWithdrawalRequests(address user) external view returns (WithdrawalRequest[] memory);
    
    /**
     * @dev Compounds rewards into the vault
     * Only callable by authorized roles (e.g., OPERATOR_ROLE)
     * @param rewardAmount The amount of rewards to compound
     * @return success Boolean indicating if the compound was successful
     */
    function compoundRewards(uint256 rewardAmount) external returns (bool success);
    
    /**
     * @dev Gets the current APY of the vault
     * @return The current APY as a percentage with 18 decimals
     */
    function getCurrentAPY() external view returns (uint256);
    
    /**
     * @dev Gets the total staked amount in the vault (both in the contract and on Cosmos)
     * @return The total staked amount with 18 decimals
     */
    function getTotalStaked() external view returns (uint256);
} 