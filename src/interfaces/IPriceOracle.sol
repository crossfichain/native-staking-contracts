// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPriceOracle {
    /// @notice Get the current price of XFI in terms of MPX
    /// @return price The current price with 18 decimals precision
    /// @return timestamp The timestamp of the last price update
    function getXFIPrice() external view returns (uint256 price, uint256 timestamp);
    
    /// @notice Get the current rewards amount available
    /// @return amount The current rewards in XFI (18 decimals)
    /// @return timestamp The timestamp of the last rewards update
    function getCurrentRewards() external view returns (uint256 amount, uint256 timestamp);
} 