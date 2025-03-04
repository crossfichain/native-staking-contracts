// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IDIAOracle
 * @dev Interface for the DIA oracle
 */
interface IDIAOracle {
    function getValue(string memory key) external view returns (uint128 price, uint128 timestamp);
    function getXFIPrice() external view returns (uint256, uint256);
    function getCurrentRewards() external view returns (uint256, uint256);
} 