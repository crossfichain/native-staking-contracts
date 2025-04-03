// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title MockDIAOracle
 * @dev A minimal mock implementation of DIA Oracle for testing deployments
 * Implements the bare minimum interface needed for the Native Staking system
 */
contract MockDIAOracle {
    mapping(string => uint128) private prices;
    mapping(string => uint128) private timestamps;
    
    event PriceSet(string key, uint128 price);
    
    /**
     * @dev Returns the price and timestamp for the given key
     * This mimics DIA Oracle's getValue function
     * @param key The price key (e.g., "XFI/USD")
     * @return price The price value (with 8 decimals typically)
     * @return timestamp The timestamp when the price was last updated
     */
    function getValue(string memory key) external view returns (uint128 price, uint128 timestamp) {
        return (prices[key], timestamps[key]);
    }
    
    /**
     * @dev Sets a price for a given key
     * @param key The price key (e.g., "XFI/USD")
     * @param value The price value (with 8 decimals typically)
     */
    function setPrice(string memory key, uint128 value) external {
        prices[key] = value;
        timestamps[key] = uint128(block.timestamp);
        emit PriceSet(key, value);
    }
} 