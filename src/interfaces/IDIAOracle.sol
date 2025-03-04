// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IDIAOracle
 * @dev Interface for the DIA oracle - only including functions that the actual DIA Oracle provides
 */
interface IDIAOracle {
    /**
     * @dev Gets the value for a given key from the DIA Oracle
     * @param key The key to get the value for (e.g., "XFI/USD")
     * @return price The price with 8 decimals of precision
     * @return timestamp The timestamp when the price was updated
     */
    function getValue(string memory key) external view returns (uint128 price, uint128 timestamp);
} 