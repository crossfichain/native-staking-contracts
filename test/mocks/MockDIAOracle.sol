// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockDIAOracle {
    mapping(string => uint256) private prices;
    uint256 private rewards;

    function setPrice(string memory key, uint256 price) external {
        prices[key] = price;
    }

    function getValue(string memory key) public view returns (uint256 price, uint256) {
        return (prices[key], block.timestamp);
    }

    function getXFIPrice() external view returns (uint256, uint256) {
        (uint256 price, uint256 timestamp) = getValue("XFI/USD");
        if (price == 0) {
            price = 1 ether;
            timestamp = block.timestamp;
        }
        return (price, timestamp);
    }

    function getCurrentRewards() external returns (uint256, uint256) {
        rewards += 100 ether;
        return (rewards, block.timestamp);
    }
} 