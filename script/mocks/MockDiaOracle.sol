// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/interfaces/IDIAOracle.sol";

/**
 * @title MockDIAOracle
 * @dev Mock DIA Oracle implementation for testing and development
 */
contract MockDIAOracle is IDIAOracle {
    // Storage for prices and timestamps
    mapping(string => uint128) private _prices;
    mapping(string => uint128) private _timestamps;
    
    /**
     * @dev Returns the current price and timestamp for the given key
     * @param key The symbol to get the price for (e.g., "XFI/USD")
     * @return price The price with 8 decimals of precision
     * @return timestamp The timestamp when the price was updated
     */
    function getValue(string memory key) external view override returns (uint128 price, uint128 timestamp) {
        return (_prices[key], _timestamps[key]);
    }
    
    /**
     * @dev Sets the price for the given key
     * @param key The symbol to update the price for
     * @param value The price with 8 decimals of precision
     */
    function setPrice(string memory key, uint128 value) external override {
        _prices[key] = value;
        _timestamps[key] = uint128(block.timestamp);
    }
} 

