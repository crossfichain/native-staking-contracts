// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title MockDIAOracle
 * @dev Mock DIA Oracle for testing
 */
contract MockDIAOracle {
    // Key-value mappings for price and APR data
    mapping(string => uint256) public prices;
    mapping(string => uint256) public timestamps;
    uint256 public apr;
    uint256 public aprUpdatedAt;
    
    /**
     * @dev Constructor
     */
    constructor() {
        // Initialize with some default values
        prices["XFI"] = 1e18; // 1 USD
        timestamps["XFI"] = block.timestamp;
        apr = 5 * 1e16; // 5% APR
        aprUpdatedAt = block.timestamp;
    }
    
    /**
     * @dev Set the price and timestamp for a token
     * @param key The token key (e.g., "XFI")
     * @param price The price in USD (18 decimals)
     * @param timestamp The timestamp of the price update
     */
    function setPrice(string memory key, uint256 price, uint256 timestamp) external {
        prices[key] = price;
        timestamps[key] = timestamp;
    }
    
    /**
     * @dev Set the APR value
     * @param _apr The APR value (18 decimals, e.g., 5e16 for 5%)
     */
    function setAPR(uint256 _apr) external {
        apr = _apr;
        aprUpdatedAt = block.timestamp;
    }
    
    /**
     * @dev Get the price and timestamp for a token
     * @param key The token key (e.g., "XFI")
     * @return The price in USD (18 decimals)
     * @return The timestamp of the price update
     */
    function getValue(string memory key) external view returns (uint256, uint256) {
        return (prices[key], timestamps[key]);
    }
    
    /**
     * @dev Get the APR value and timestamp
     * @return The APR value (18 decimals)
     * @return The timestamp of the APR update
     */
    function getAPR() external view returns (uint256, uint256) {
        return (apr, aprUpdatedAt);
    }
} 