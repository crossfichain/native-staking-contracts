// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IDIAOracle
 * @dev Interface for DIA Oracle price feed
 */
interface IDIAOracle {
    /**
     * @dev Returns the current price and timestamp for the given key
     * @param key The symbol to get the price for (e.g., "XFI/USD")
     * @return price The price with 8 decimals of precision
     * @return timestamp The timestamp when the price was updated
     */
    function getValue(string memory key) external view returns (uint128 price, uint128 timestamp);
    
    /**
     * @dev Sets the price for the given key (used in test mocks)
     * @param key The symbol to update the price for
     * @param value The price with 8 decimals of precision
     */
    function setPrice(string memory key, uint128 value) external;
} 