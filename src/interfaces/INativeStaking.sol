// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title INativeStaking
 * @dev Interface for the Native Staking contract that handles staking operations
 * Validator information is passed to events for off-chain processing
 */
interface INativeStaking {
    /**
     * @dev Struct to store stake information
     * @param amount The amount of XFI staked
     * @param stakedAt The timestamp when the stake was created
     * @param unbondingAt The timestamp when unbonding was requested (0 if not unbonding)
     * @param validator The validator address/ID associated with this stake
     */
    struct StakeInfo {
        uint256 amount;
        uint256 stakedAt;
        uint256 unbondingAt;
        string validator;
    }
    
    /**
     * @dev Struct to track pending unstake requests
     * @param amount The amount to unstake
     * @param unlockTime The timestamp when funds can be claimed
     * @param completed Whether the unstake has been completed (claimed)
     */
    struct UnstakeRequest {
        uint256 amount;
        uint256 unlockTime;
        bool completed;
    }
    
    /**
     * @dev Stakes XFI with validator information passed to events
     * @param user The user who is staking
     * @param amount The amount of XFI to stake
     * @param validator The validator address/ID (only used in events, not stored)
     * @param tokenAddress The address of token being staked (XFI or WXFI)
     * @return success Boolean indicating if the stake was successful
     */
    function stake(address user, uint256 amount, string calldata validator, address tokenAddress) external returns (bool success);
    
    /**
     * @dev Requests to unstake XFI with validator information passed to events
     * @param user The user who is unstaking
     * @param amount The amount of XFI to unstake
     * @param validator The validator address/ID (only used in events, not stored)
     * @return requestId The ID of the unstake request
     */
    function requestUnstake(address user, uint256 amount, string calldata validator) external returns (bytes memory requestId);
    
    /**
     * @dev Claims XFI from a completed unstake request
     * @param user The user claiming the unstaked XFI
     * @param requestId The ID of the unstake request to claim
     * @return amount The amount of XFI claimed
     */
    function claimUnstake(address user, bytes calldata requestId) external returns (uint256 amount);
    
    /**
     * @dev Claims staking rewards for a user
     * @param user The user to claim rewards for
     * @param rewardAmount The amount of rewards to claim (determined by oracle)
     * @return amount The amount of rewards claimed
     */
    function claimRewards(address user, uint256 rewardAmount) external returns (uint256 amount);
    
    /**
     * @dev Gets all active stakes for a user
     * @param user The user to get stakes for
     * @return An array of StakeInfo structs
     */
    function getUserStakes(address user) external view returns (StakeInfo[] memory);
    
    /**
     * @dev Gets all pending unstake requests for a user
     * @param user The user to get unstake requests for
     * @return An array of UnstakeRequest structs
     */
    function getUserUnstakeRequests(address user) external view returns (UnstakeRequest[] memory);
    
    /**
     * @dev Gets a specific unstake request for a user
     * @param user The user to get the request for
     * @param requestId The ID of the request
     * @return The UnstakeRequest struct
     */
    function getUnstakeRequest(address user, bytes calldata requestId) external view returns (UnstakeRequest memory);
    
    /**
     * @dev Gets the total amount of XFI staked by a user
     * @param user The user to get the total for
     * @return The total amount of XFI staked
     */
    function getTotalStaked(address user) external view returns (uint256);
    
    /**
     * @dev Gets the amount staked with a specific validator
     * @param user The user address
     * @param validator The validator address
     * @return The amount staked with the validator
     */
    function getValidatorStake(address user, string calldata validator) external view returns (uint256);
    
    /**
     * @dev Gets the total amount of unclaimed rewards for a user
     * @param user The user to get the rewards for
     * @return The total amount of unclaimed rewards
     */
    function getUnclaimedRewards(address user) external view returns (uint256);
} 