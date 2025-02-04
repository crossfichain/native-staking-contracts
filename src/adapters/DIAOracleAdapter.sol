// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IDIAOracle} from "../interfaces/IDIAOracle.sol";

contract DIAOracleAdapter is IPriceOracle {
    IDIAOracle public immutable diaOracle;
    string public constant XFI_PRICE_KEY = "XFI/USD";
    
    // Constants for decimal conversion
    uint256 private constant DIA_DECIMALS = 8;
    uint256 private constant TARGET_DECIMALS = 18;
    uint256 private constant SCALING_FACTOR = 10 ** (TARGET_DECIMALS - DIA_DECIMALS);
    
    constructor(address _diaOracle) {
        require(_diaOracle != address(0), "DIAOracleAdapter: Zero address");
        diaOracle = IDIAOracle(_diaOracle);
    }
    
    /// @notice Get XFI price normalized to 18 decimals
    /// @return price The current price with 18 decimals precision
    /// @return timestamp The timestamp of the last price update
    function getXFIPrice() external view returns (uint256 price, uint256 timestamp) {
        (uint128 rawPrice, uint128 _timestamp) = diaOracle.getValue(XFI_PRICE_KEY);
        
        // Convert 8 decimals to 18 decimals
        price = uint256(rawPrice) * SCALING_FACTOR;
        timestamp = uint256(_timestamp);
        
        require(price > 0, "DIAOracleAdapter: Invalid price");
        require(
            timestamp > block.timestamp - 1 days,
            "DIAOracleAdapter: Stale price"
        );
    }
    
    /// @notice Get current rewards amount in 18 decimals precision
    function getCurrentRewards() external view returns (uint256 amount, uint256 timestamp) {
        (uint128 rawAmount, uint128 _timestamp) = diaOracle.getValue("REWARDS");
        
        // Convert 8 decimals to 18 decimals
        amount = uint256(rawAmount) * SCALING_FACTOR;
        timestamp = uint256(_timestamp);
        
        require(amount > 0, "DIAOracleAdapter: Invalid reward amount");
        require(
            timestamp > block.timestamp - 1 days,
            "DIAOracleAdapter: Stale rewards data"
        );
    }

    /// @notice Helper function to convert DIA price to 18 decimals
    /// @param diaPrice Price with 8 decimals
    /// @return Price with 18 decimals
    function normalizePrice(uint256 diaPrice) public pure returns (uint256) {
        return diaPrice * SCALING_FACTOR;
    }

    /// @notice Helper function to convert 18 decimals to DIA decimals
    /// @param price Price with 18 decimals
    /// @return Price with 8 decimals
    function denormalizePrice(uint256 price) public pure returns (uint256) {
        return price / SCALING_FACTOR;
    }
} 