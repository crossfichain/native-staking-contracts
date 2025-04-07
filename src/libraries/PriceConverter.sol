// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../interfaces/IOracle.sol";

/**
 * @title PriceConverter
 * @dev Library for token price conversion utilities
 */
library PriceConverter {
    /**
     * @dev Converts XFI amount to MPX amount using the oracle
     * @param oracle The oracle contract with price data
     * @param xfiAmount The amount of XFI to convert
     * @return The equivalent amount of MPX tokens
     */
    function toMPX(IOracle oracle, uint256 xfiAmount) internal view returns (uint256) {
        if (xfiAmount == 0) return 0;
        
        // Get prices from the oracle
        uint256 xfiPrice = oracle.getPrice("XFI");
        uint256 mpxPrice = oracle.getMPXPrice();
        
        // If either price is zero, we can't perform the conversion
        if (xfiPrice == 0 || mpxPrice == 0) return 0;
        
        // Convert using cross-multiplication: 
        // xfiAmount * xfiPrice / mpxPrice = mpxAmount
        return (xfiAmount * xfiPrice) / mpxPrice;
    }
    
    /**
     * @dev Converts XFI amount to USD value
     * @param oracle The oracle contract with price data
     * @param xfiAmount The amount of XFI to convert
     * @return The USD value of the XFI amount
     */
    function toUSD(IOracle oracle, uint256 xfiAmount) internal view returns (uint256) {
        if (xfiAmount == 0) return 0;
        
        // Get XFI price from the oracle
        uint256 xfiPrice = oracle.getPrice("XFI");
        
        // Convert using multiplication
        return xfiAmount * xfiPrice / 1e18;
    }
} 