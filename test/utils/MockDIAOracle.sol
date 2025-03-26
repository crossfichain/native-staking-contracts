// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/interfaces/IDIAOracle.sol";

/**
 * @title MockDIAOracle
 * @dev Mock implementation of the DIA Oracle for testing purposes
 * Returns prices with 8 decimals of precision to mimic the real DIA Oracle
 */
contract MockDIAOracle is IDIAOracle {
    // Mapping from key to price (with 8 decimals)
    mapping(string => uint128) private _prices;
    
    // Mapping from key to timestamp
    mapping(string => uint128) private _timestamps;
    
    /**
     * @dev Constructor
     */
    constructor() {
        // Set default XFI price to $1 with 8 decimals
        _prices["XFI/USD"] = 1 * 10**8;
        _timestamps["XFI/USD"] = uint128(block.timestamp);
    }
    
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
    
    /**
     * @dev Sets the price for the given key with a specific timestamp
     * @param key The symbol to update the price for
     * @param value The price with 8 decimals of precision
     * @param timestamp The timestamp to set
     */
    function setPriceWithTimestamp(string memory key, uint128 value, uint128 timestamp) external {
        _prices[key] = value;
        _timestamps[key] = timestamp;
    }

    function addUserClaimableRewards(address user, uint256 amount) external {
        // This is a mock function for testing
        // In a real implementation, this would be handled by the UnifiedOracle
    }
} 