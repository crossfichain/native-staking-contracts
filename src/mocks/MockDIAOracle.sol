// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDIAOracle} from "../../src/interfaces/IDIAOracle.sol";

contract MockDIAOracle is IDIAOracle {
    mapping(string => uint256) private prices;
    uint256 private rewards;
    uint256 private lastUpdateTimestamp;
    bool private shouldRevert;

    event PriceSet(string key, uint256 price);
    event RewardsSet(uint256 rewards);

    function setPrice(string memory key, uint256 price) external {
        // Price should already be in 8 decimals
        prices[key] = price;
        lastUpdateTimestamp = block.timestamp;
        emit PriceSet(key, prices[key]);
    }

    function getValue(string memory key) public view returns (uint128 price, uint128 timestamp) {
        require(!shouldRevert, "MockDIAOracle: Forced revert");
        return (uint128(prices[key]), uint128(lastUpdateTimestamp));
    }

    function getXFIPrice() external view returns (uint256, uint256) {
        require(!shouldRevert, "MockDIAOracle: Forced revert");
        (uint256 price, uint256 timestamp) = getValue("XFI/USD");
        if (price == 0) {
            price = 1e8; // 1 USD in 8 decimals
            timestamp = block.timestamp;
        }
        return (price, timestamp);
    }

    function setRewards(uint256 _rewards) external {
        // Convert from 18 decimals to 8 decimals
        rewards = _rewards / 1e10;
        lastUpdateTimestamp = block.timestamp;
        emit RewardsSet(rewards);
    }

    function getCurrentRewards() external view returns (uint256, uint256) {
        require(!shouldRevert, "MockDIAOracle: Forced revert");
        return (rewards, lastUpdateTimestamp);
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
} 