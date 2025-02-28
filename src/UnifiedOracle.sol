// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUnifiedOracle} from "./interfaces/IUnifiedOracle.sol";
import {IDIAOracle} from "./interfaces/IDIAOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title UnifiedOracle
 * @notice Oracle contract to fetch XFI price and distribute rewards
 * @dev Uses DIA Oracle for price feeds with fallback mechanism
 */
contract UnifiedOracle is IUnifiedOracle, AccessControl {
    using Math for uint256;

    // Constants
    uint256 private constant DIA_DECIMALS = 8;
    uint256 private constant TARGET_DECIMALS = 18;
    uint256 private constant SCALING_FACTOR = 10 ** (TARGET_DECIMALS - DIA_DECIMALS);
    uint256 private constant MAX_STALENESS = 1 days;

    // Roles
    bytes32 public constant ORACLE_ADMIN = keccak256("ORACLE_ADMIN");

    // State
    IDIAOracle public diaOracle;
    IDIAOracle public fallbackOracle;
    string public constant XFI_PRICE_KEY = "XFI/USD";
    
    // Rewards state
    uint256 public rewardsAmount;
    uint256 public rewardsTimestamp;
    uint256 public rewardsPeriodStart;
    uint256 public rewardsPeriodEnd;
    
    // Events
    event DIAOracleUpdated(address indexed newOracle);
    event FallbackOracleUpdated(address indexed newOracle);
    event RewardsUpdated(uint256 amount, uint256 periodStart, uint256 periodEnd);

    /**
     * @dev Constructor sets up the oracle and roles
     * @param _diaOracle DIA Oracle address
     * @param _admin Admin address for oracle management
     */
    constructor(address _diaOracle, address _admin) {
        require(_diaOracle != address(0), "UnifiedOracle: Zero oracle address");
        
        diaOracle = IDIAOracle(_diaOracle);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ADMIN, _admin);
        
        // Initialize rewards
        rewardsTimestamp = block.timestamp;
        rewardsPeriodStart = block.timestamp;
        rewardsPeriodEnd = block.timestamp + 30 days;
    }
    
    /**
     * @notice Set the DIA Oracle address
     * @dev Only callable by admin
     * @param _diaOracle New DIA Oracle address
     */
    function setDIAOracle(address _diaOracle) external onlyRole(ORACLE_ADMIN) {
        require(_diaOracle != address(0), "UnifiedOracle: Zero oracle address");
        diaOracle = IDIAOracle(_diaOracle);
        
        emit DIAOracleUpdated(_diaOracle);
    }
    
    /**
     * @notice Set the fallback oracle address
     * @dev Only callable by admin
     * @param _fallbackOracle New fallback oracle address
     */
    function setFallbackOracle(address _fallbackOracle) external onlyRole(ORACLE_ADMIN) {
        require(_fallbackOracle != address(0), "UnifiedOracle: Zero oracle address");
        fallbackOracle = IDIAOracle(_fallbackOracle);
        
        emit FallbackOracleUpdated(_fallbackOracle);
    }
    
    /**
     * @notice Update the current rewards amount and period
     * @dev Only callable by admin
     * @param _amount New rewards amount
     * @param _periodStart Start timestamp of rewards period
     * @param _periodEnd End timestamp of rewards period
     */
    function updateRewards(
        uint256 _amount,
        uint256 _periodStart,
        uint256 _periodEnd
    ) external onlyRole(ORACLE_ADMIN) {
        require(_periodEnd > _periodStart, "UnifiedOracle: Invalid period");
        
        rewardsAmount = _amount;
        rewardsTimestamp = block.timestamp;
        rewardsPeriodStart = _periodStart;
        rewardsPeriodEnd = _periodEnd;
        
        emit RewardsUpdated(_amount, _periodStart, _periodEnd);
    }
    
    /**
     * @notice Get the XFI price from the oracle
     * @dev Returns the price in USD with 18 decimals
     * @return price Current XFI price
     * @return timestamp Timestamp of the price
     */
    function getXFIPrice() external view returns (uint256 price, uint256 timestamp) {
        try diaOracle.getValue(XFI_PRICE_KEY) returns (uint128 _price, uint128 _timestamp) {
            if (block.timestamp - _timestamp <= MAX_STALENESS) {
                return (uint256(_price) * SCALING_FACTOR, _timestamp);
            }
        } catch {}
        
        // Try fallback if primary fails or is stale
        if (address(fallbackOracle) != address(0)) {
            try fallbackOracle.getValue(XFI_PRICE_KEY) returns (uint128 _price, uint128 _timestamp) {
                if (block.timestamp - _timestamp <= MAX_STALENESS) {
                    return (uint256(_price) * SCALING_FACTOR, _timestamp);
                }
            } catch {}
        }
        
        revert("UnifiedOracle: No fresh price data");
    }
    
    /**
     * @notice Get the current rewards data
     * @dev Returns rewards amount and timestamp
     * @return amount Current rewards amount
     * @return timestamp Timestamp when rewards were last updated
     */
    function getCurrentRewards() external view returns (uint256 amount, uint256 timestamp) {
        return (rewardsAmount, rewardsTimestamp);
    }
    
    /**
     * @notice Check if the oracle has fresh data
     * @dev Returns true if at least one oracle has fresh data
     * @return bool True if oracle data is fresh
     */
    function isOracleFresh() external view returns (bool) {
        try diaOracle.getValue(XFI_PRICE_KEY) returns (uint128, uint128 _timestamp) {
            if (block.timestamp - _timestamp <= MAX_STALENESS) {
                return true;
            }
        } catch {}
        
        // Try fallback if primary fails or is stale
        if (address(fallbackOracle) != address(0)) {
            try fallbackOracle.getValue(XFI_PRICE_KEY) returns (uint128, uint128 _timestamp) {
                if (block.timestamp - _timestamp <= MAX_STALENESS) {
                    return true;
                }
            } catch {}
        }
        
        return false;
    }
    
    /**
     * @notice Get the rewards period
     * @dev Returns start and end timestamps
     * @return start Period start timestamp
     * @return end Period end timestamp
     */
    function getRewardsPeriod() external view returns (uint256 start, uint256 end) {
        return (rewardsPeriodStart, rewardsPeriodEnd);
    }
} 