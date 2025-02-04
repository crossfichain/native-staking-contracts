// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockDIAOracle {
    mapping(string => uint256) private prices;

    function setPrice(string memory key, uint256 price) external {
        prices[key] = price;
    }

    function getValue(string memory key) external view returns (uint256 price, uint256) {
        return (prices[key], block.timestamp);
    }
} 