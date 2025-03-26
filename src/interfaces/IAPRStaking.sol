// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAPRStaking {
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
     */
    function requestUnstake(
        address user,
        uint256 amount,
        string calldata validator
    ) external;

    /**
     * @dev Claims unstaked XFI tokens after the unbonding period
     * @param user The address of the user claiming
     * @param requestId The ID of the unstake request
     * @return amount The amount of XFI claimed
     */
    function claimUnstake(
        address user,
        uint256 requestId
    ) external returns (uint256 amount);

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
} 