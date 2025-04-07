// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/interfaces/IOracle.sol";

contract MockOracle is IOracle {
    uint256 private _xfiPrice = 1e18; // Default: 1 USD per XFI
    uint256 private _mpxPrice = 0.01e18; // Default: 0.01 USD per MPX
    uint256 private _lastUpdated;
    
    constructor() {
        _lastUpdated = block.timestamp;
    }
    
    function getPrice(string calldata symbol) external view override returns (uint256) {
        if (keccak256(abi.encodePacked(symbol)) == keccak256(abi.encodePacked("XFI"))) {
            return _xfiPrice;
        } else if (keccak256(abi.encodePacked(symbol)) == keccak256(abi.encodePacked("MPX"))) {
            return _mpxPrice;
        }
        return 0;
    }
    
    function getXFIPrice() external view override returns (uint256 price, uint256 timestamp) {
        return (_xfiPrice, _lastUpdated);
    }
    
    function convertXFItoMPX(uint256 xfiAmount) external view override returns (uint256) {
        // 1 XFI = (_xfiPrice / _mpxPrice) MPX
        return (xfiAmount * _xfiPrice) / _mpxPrice;
    }
    
    function setMPXPrice(uint256 price) external override {
        _mpxPrice = price;
        _lastUpdated = block.timestamp;
    }
    
    function getMPXPrice() external view override returns (uint256) {
        return _mpxPrice;
    }
    
    // Additional test functions
    function setXFIPrice(uint256 price) external {
        _xfiPrice = price;
        _lastUpdated = block.timestamp;
    }
    
    function setTimestamp(uint256 timestamp) external {
        _lastUpdated = timestamp;
    }
} 