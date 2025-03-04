// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IUnifiedOracle
 * @dev Interface for the unified oracle system
 */
interface IUnifiedOracle {
    function getXFIPrice() external view returns (uint256, uint256);
    function getCurrentRewards() external view returns (uint256, uint256);
    function setDIAOracle(address oracle) external;
    function setFallbackOracle(address oracle) external;
    function isOracleFresh() external view returns (bool);
} 