// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDIAOracle
 * @notice Interface for interacting with DIA Oracle
 * @dev Provides price data with key-based lookup
 */
interface IDIAOracle {
    /**
     * @notice Get a value from the oracle
     * @param key The key to look up (e.g., "XFI/USD")
     * @return price The price value with 8 decimals
     * @return timestamp The timestamp when the price was updated
     */
    function getValue(string memory key) external view returns (uint128 price, uint128 timestamp);
}
