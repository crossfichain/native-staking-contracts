// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IOracle
 * @notice Interface for the Oracle contract
 * @dev Defines the oracle functionality for price data and reward rates
 */
interface IOracle {
    // ============ Events ============
    event OracleUpdated(address indexed newOracle);
    event XFIPriceKeyUpdated(string newKey);
    event RewardRateUpdated(uint256 newRate);
    event RewardPeriodUpdated(uint256 start, uint256 end);
    
    // ============ Admin Functions ============
    
    function setDIAOracle(address _diaOracle) external;
    
    function setXFIPriceKey(string calldata _xfiPriceKey) external;
    
    function updateRewardRate(uint256 _rewardRate) external;
    
    function setRewardPeriod(uint256 _start, uint256 _end) external;
    
    // ============ View Functions ============
    
    function getXFIPrice() external view returns (uint256 price, uint256 timestamp);
    
    function getCurrentRewardRate() external view returns (uint256 rate, uint256 timestamp);
    
    function getCurrentAPR() external view returns (uint256);
    
    function isOracleFresh() external view returns (bool);
    
    function getRewardPeriod() external view returns (uint256 start, uint256 end);
} 