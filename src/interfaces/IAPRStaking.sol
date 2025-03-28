// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAPRStaking {
    // Define UnstakeRequest struct for interface
    struct UnstakeRequest {
        address user;
        uint256 amount;
        string validator;
        uint256 timestamp;
        bool claimed;
    }

    /**
     * @dev Stakes XFI tokens for a specific validator
     * @param user The address of the user staking
     * @param amount The amount of XFI to stake
     * @param validator The validator address to stake with
     * @param token The token address (WXFI)
     * @return success Whether the stake was successful
     */
    function stake(
        address user,
        uint256 amount,
        string calldata validator,
        address token
    ) external returns (bool success);

    /**
     * @dev Requests to unstake XFI tokens from a validator
     * @param user The address of the user unstaking
     * @param amount The amount of XFI to unstake
     * @param validator The validator address to unstake from
     * @return requestId The ID of the unstake request
     */
    function requestUnstake(
        address user,
        uint256 amount,
        string calldata validator
    ) external returns (bytes memory requestId);

    /**
     * @dev Claims unstaked XFI tokens after the unbonding period
     * @param user The address of the user claiming
     * @param requestId The ID of the unstake request
     * @return amount The amount of XFI claimed
     */
    function claimUnstake(
        address user,
        bytes calldata requestId
    ) external returns (uint256 amount);

    /**
     * @dev Gets details of an unstake request
     * @param requestId The ID of the unstake request
     * @return The unstake request details
     */
    function getUnstakeRequest(
        bytes calldata requestId
    ) external view returns (UnstakeRequest memory);

    /**
     * @dev Claims accumulated rewards
     * @param user The address of the user claiming rewards
     * @param amount The amount of rewards to claim
     */
    function claimRewards(
        address user,
        uint256 amount
    ) external;

    /**
     * @dev Gets the total amount staked by a user
     * @param user The address of the user
     * @return The total amount staked
     */
    function getTotalStaked(address user) external view returns (uint256);

    /**
     * @dev Gets the total amount staked across all users
     * @return The total amount staked
     */
    function getTotalStaked() external view returns (uint256);

    /**
     * @dev Gets the amount staked with a specific validator
     * @param user The address of the user
     * @param validator The validator address
     * @return The amount staked with the validator
     */
    function getValidatorStake(
        address user,
        string calldata validator
    ) external view returns (uint256);

    /**
     * @dev Gets all validators a user has staked with
     * @param user The address of the user
     * @return An array of validator addresses
     */
    function getUserValidators(address user) external view returns (string[] memory);
    
    /**
     * @dev Gets the latest request ID that was created
     * @return The latest request ID (bytes)
     */
    function getLatestRequestId() external view returns (bytes memory);

    /**
     * @dev Claims accumulated rewards from a specific validator
     * @param user The address of the user claiming rewards
     * @param validator The validator to claim rewards from
     * @param amount The amount of rewards to claim
     * @return The amount claimed
     */
    function claimRewardsForValidator(
        address user,
        string calldata validator,
        uint256 amount
    ) external returns (uint256);
} 