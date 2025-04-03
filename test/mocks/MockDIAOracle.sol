// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IDIAOracle} from "../../src/interfaces/IDIAOracle.sol";

contract MockDIAOracle is IDIAOracle {
    mapping(string => uint128) private prices;
    uint256 private rewards;
    uint128 private lastUpdateTimestamp;
    bool private shouldRevert;

    event PriceSet(string key, uint128 price);
    event RewardsSet(uint256 rewards);

    function setPrice(string memory key, uint128 value) external override {
        // Price should already be in 8 decimals
        prices[key] = value;
        lastUpdateTimestamp = uint128(block.timestamp);
        emit PriceSet(key, prices[key]);
    }

    function getValue(string memory key) public view returns (uint128 price, uint128 timestamp) {
        require(!shouldRevert, "MockDIAOracle: Forced revert");
        return (prices[key], lastUpdateTimestamp);
    }

    function getXFIPrice() external view returns (uint256, uint256) {
        require(!shouldRevert, "MockDIAOracle: Forced revert");
        (uint128 price, uint128 timestamp) = getValue("XFI/USD");
        if (price == 0) {
            price = 1e8; // 1 USD in 8 decimals
            timestamp = uint128(block.timestamp);
        }
        return (price, timestamp);
    }

    function setRewards(uint256 _rewards) external {
        // Convert from 18 decimals to 8 decimals
        rewards = _rewards / 1e10;
        lastUpdateTimestamp = uint128(block.timestamp);
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