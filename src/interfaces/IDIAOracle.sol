// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IDIAOracle
 * @dev Interface for the DIA Oracle which provides price data with 8 decimals
 * This interface allows the Native Staking system to obtain XFI price from the DIA Oracle
 */
interface IDIAOracle {
    /**
     * @dev Returns the latest price for the given symbol
     * @param key The symbol to get the price for (e.g., "XFI/USD")
     * @return price The price with 8 decimals of precision
     * @return timestamp The timestamp when the price was updated
     */
    function getValue(string memory key) external view returns (uint128 price, uint128 timestamp);
    
    /**
     * @dev Sets the price for the given symbol (only accessible by oracle updaters)
     * @param key The symbol to update the price for
     * @param value The price with 8 decimals of precision
     */
    function setPrice(string memory key, uint128 value) external;
} 