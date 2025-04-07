// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IOracle
 * @dev Interface for Oracle contract with price feeds and conversion functions
 */
interface IOracle {
    /**
     * @dev Returns the current price for the given asset
     * @param symbol The symbol to get the price for (e.g., "XFI")
     * @return The price with 18 decimals of precision
     */
    function getPrice(string calldata symbol) external view returns (uint256);
    
    /**
     * @dev Returns the current XFI price with timestamp
     * @return price The XFI price with 18 decimals
     * @return timestamp The timestamp when the price was updated
     */
    function getXFIPrice() external view returns (uint256 price, uint256 timestamp);
    
    /**
     * @dev Converts XFI to MPX based on current prices
     * @param xfiAmount The amount of XFI to convert
     * @return The equivalent amount of MPX
     */
    function convertXFItoMPX(uint256 xfiAmount) external view returns (uint256);
    
    /**
     * @dev Sets the MPX/USD price
     * @param price The MPX/USD price with 18 decimals
     */
    function setMPXPrice(uint256 price) external;
    
    /**
     * @dev Returns the current MPX/USD price
     * @return The MPX/USD price with 18 decimals
     */
    function getMPXPrice() external view returns (uint256);
} 