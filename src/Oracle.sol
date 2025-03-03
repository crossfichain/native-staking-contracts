// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IDIAOracle} from "./interfaces/IDIAOracle.sol";

/**
 * @title Oracle
 * @notice Simple oracle for XFI price data and reward rates
 * @dev Focuses only on essential price and reward functionality
 */
contract Oracle is AccessControl {
    // ============ Constants ============
    uint256 private constant PRECISION = 1e18;
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MAX_STALENESS = 1 days;
    
    // ============ Roles ============
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    
    // ============ State Variables ============
    
    // DIA Oracle integration
    IDIAOracle public diaOracle;
    string public xfiPriceKey;
    
    // Reward rate data
    uint256 public rewardRate;               // Current reward rate in basis points
    uint256 public rewardRateLastUpdate;     // Timestamp of last reward rate update
    
    // Reward periods
    uint256 public rewardPeriodStart;        // Start of current reward period
    uint256 public rewardPeriodEnd;          // End of current reward period
    
    // ============ Events ============
    event OracleUpdated(address indexed newOracle);
    event XFIPriceKeyUpdated(string newKey);
    event RewardRateUpdated(uint256 newRate);
    event RewardPeriodUpdated(uint256 start, uint256 end);
    
    // ============ Constructor ============
    constructor(
        address _diaOracle,
        string memory _xfiPriceKey,
        uint256 _initialRewardRate
    ) {
        require(_diaOracle != address(0), "Oracle: Zero address");
        require(bytes(_xfiPriceKey).length > 0, "Oracle: Empty key");
        
        diaOracle = IDIAOracle(_diaOracle);
        xfiPriceKey = _xfiPriceKey;
        rewardRate = _initialRewardRate;
        
        // Set current timestamp for initial updates
        rewardRateLastUpdate = block.timestamp;
        
        // Set initial reward period (30 days by default)
        rewardPeriodStart = block.timestamp;
        rewardPeriodEnd = block.timestamp + 30 days;
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Set DIA Oracle address
     * @param _diaOracle New DIA Oracle address
     */
    function setDIAOracle(address _diaOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_diaOracle != address(0), "Oracle: Zero address");
        diaOracle = IDIAOracle(_diaOracle);
        emit OracleUpdated(_diaOracle);
    }
    
    /**
     * @notice Set XFI price key for DIA Oracle
     * @param _xfiPriceKey New XFI price key
     */
    function setXFIPriceKey(string calldata _xfiPriceKey) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bytes(_xfiPriceKey).length > 0, "Oracle: Empty key");
        xfiPriceKey = _xfiPriceKey;
        emit XFIPriceKeyUpdated(_xfiPriceKey);
    }
    
    /**
     * @notice Update reward rate
     * @param _rewardRate New reward rate in basis points
     */
    function updateRewardRate(uint256 _rewardRate) external onlyRole(ORACLE_ROLE) {
        rewardRate = _rewardRate;
        rewardRateLastUpdate = block.timestamp;
        emit RewardRateUpdated(_rewardRate);
    }
    
    /**
     * @notice Set reward period
     * @param _start Start timestamp
     * @param _end End timestamp
     */
    function setRewardPeriod(uint256 _start, uint256 _end) external onlyRole(ORACLE_ROLE) {
        require(_end > _start, "Oracle: Invalid period");
        rewardPeriodStart = _start;
        rewardPeriodEnd = _end;
        emit RewardPeriodUpdated(_start, _end);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get XFI price from DIA Oracle
     * @return price Current XFI price (scaled to 18 decimals)
     * @return timestamp Timestamp of price update
     */
    function getXFIPrice() external view returns (uint256 price, uint256 timestamp) {
        try diaOracle.getValue(xfiPriceKey) returns (uint128 _price, uint128 _timestamp) {
            // DIA prices have 8 decimals, convert to 18
            price = uint256(_price) * (PRECISION / 1e8);
            timestamp = _timestamp;
        } catch {
            revert("Oracle: Failed to get price");
        }
        
        // Check for stale data
        require(block.timestamp - timestamp <= MAX_STALENESS, "Oracle: Stale price data");
        
        return (price, timestamp);
    }
    
    /**
     * @notice Get current reward rate
     * @return rate Current reward rate in basis points
     * @return timestamp Timestamp of last update
     */
    function getCurrentRewardRate() external view returns (uint256 rate, uint256 timestamp) {
        return (rewardRate, rewardRateLastUpdate);
    }
    
    /**
     * @notice Get current APR (Annual Percentage Rate)
     * @return Current APR in basis points
     */
    function getCurrentAPR() external view returns (uint256) {
        return rewardRate;
    }
    
    /**
     * @notice Check if oracle has fresh data
     * @return True if data is fresh
     */
    function isOracleFresh() external view returns (bool) {
        try diaOracle.getValue(xfiPriceKey) returns (uint128, uint128 timestamp) {
            return (block.timestamp - timestamp <= MAX_STALENESS);
        } catch {
            return false;
        }
    }
    
    /**
     * @notice Get reward period
     * @return start Start timestamp
     * @return end End timestamp
     */
    function getRewardPeriod() external view returns (uint256 start, uint256 end) {
        return (rewardPeriodStart, rewardPeriodEnd);
    }
} 