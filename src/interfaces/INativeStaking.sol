// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title INativeStaking
 * @dev Interface for the NativeStaking contract
 */
interface INativeStaking {
    // Struct for unstake requests
    struct UnstakeRequest {
        address user;
        uint256 amount;
        string validator;
        uint256 timestamp;
        uint256 unlockTime;
        bool claimed;
    }

    function stake(address user, uint256 amount, string calldata validator, address tokenAddress) external returns (bool);
    function unstake(address user, uint256 amount, string calldata validator) external;
    function claimRewards(address user, uint256 rewardAmount) external returns (uint256);
    function getTotalStake(address user) external view returns (uint256);
    function getPendingRewards(address user) external view returns (uint256);
    function requestUnstake(address user, uint256 amount, string calldata validator) external returns (bytes memory);
    function getUnstakeRequest(bytes calldata requestId) external view returns (UnstakeRequest memory);
    function getLatestRequestId() external view returns (bytes memory);
    function getValidatorStake(address user, string calldata validator) external view returns (uint256);
    function claimUnstake(address user, bytes calldata requestId) external returns (uint256);
    function getTotalStaked(address user) external view returns (uint256);
} 