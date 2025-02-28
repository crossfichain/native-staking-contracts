// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUnifiedOracle} from "../../src/interfaces/IUnifiedOracle.sol";

contract MockUnifiedOracle is IUnifiedOracle {
    uint256 private xfiPrice;
    uint256 private rewardsAmount;
    uint256 private lastUpdateTimestamp;
    bool private isFresh = true;

    event PriceSet(uint256 price);
    event RewardsSet(uint256 rewards);

    constructor() {
        lastUpdateTimestamp = block.timestamp;
        xfiPrice = 1 ether; // 1 USD in 18 decimals
    }

    function setXFIPrice(uint256 _price) external {
        xfiPrice = _price;
        lastUpdateTimestamp = block.timestamp;
        emit PriceSet(_price);
    }

    function setRewards(uint256 _rewards) external {
        rewardsAmount = _rewards;
        lastUpdateTimestamp = block.timestamp;
        emit RewardsSet(_rewards);
    }

    function setIsFresh(bool _isFresh) external {
        isFresh = _isFresh;
    }

    function getXFIPrice() external view returns (uint256, uint256) {
        return (xfiPrice, lastUpdateTimestamp);
    }

    function getCurrentRewards() external view returns (uint256, uint256) {
        return (rewardsAmount, lastUpdateTimestamp);
    }

    function setDIAOracle(address) external {}

    function setFallbackOracle(address) external {}

    function isOracleFresh() external view returns (bool) {
        return isFresh;
    }
} 