// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IUnifiedOracle
 * @notice Interface for the unified oracle system
 * @dev Provides price and rewards data with fallback functionality
 */
interface IUnifiedOracle {
    /**
     * @notice Get the XFI price from the oracle
     * @dev Returns the price in USD with 18 decimals
     * @return price Current XFI price
     * @return timestamp Timestamp of the price
     */
    function getXFIPrice() external view returns (uint256 price, uint256 timestamp);
    
    /**
     * @notice Get the current rewards data
     * @dev Returns rewards amount and timestamp
     * @return amount Current rewards amount
     * @return timestamp Timestamp when rewards were last updated
     */
    function getCurrentRewards() external view returns (uint256 amount, uint256 timestamp);
    
    /**
     * @notice Set the DIA Oracle address
     * @dev Only callable by admin
     * @param diaOracle New DIA Oracle address
     */
    function setDIAOracle(address diaOracle) external;
    
    /**
     * @notice Set the fallback oracle address
     * @dev Only callable by admin
     * @param fallbackOracle New fallback oracle address
     */
    function setFallbackOracle(address fallbackOracle) external;
    
    /**
     * @notice Check if the oracle has fresh data
     * @dev Returns true if at least one oracle has fresh data
     * @return bool True if oracle data is fresh
     */
    function isOracleFresh() external view returns (bool);
    
    /**
     * @notice Get the rewards period
     * @dev Returns start and end timestamps
     * @return start Period start timestamp
     * @return end Period end timestamp
     */
    function getRewardsPeriod() external view returns (uint256 start, uint256 end);
} 