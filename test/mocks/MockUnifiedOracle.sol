// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IUnifiedOracle} from "../../src/interfaces/IUnifiedOracle.sol";

contract MockUnifiedOracle is IUnifiedOracle {
    uint256 private xfiPrice;
    uint256 private rewardsAmount;
    uint256 private apyAmount;
    uint256 private totalStakedXFI;
    uint256 private validatorAPR;
    uint256 private unbondingPeriod;
    uint256 private lastUpdateTimestamp;
    bool private isFresh = true;
    mapping(string => uint256) private prices;
    uint256 private _currentAPR;

    event PriceSet(uint256 price);
    event RewardsSet(uint256 rewards);

    constructor() {
        lastUpdateTimestamp = block.timestamp;
        xfiPrice = 1 ether; // 1 USD in 18 decimals
        apyAmount = 8 * 1e16; // 8% in 18 decimals
        validatorAPR = 10 * 1e16; // 10% in 18 decimals
        unbondingPeriod = 14 days;
        totalStakedXFI = 1000000 ether;
        prices["XFI"] = 1 ether;
        _currentAPR = validatorAPR;
    }

    function setXFIPrice(uint256 _price) external {
        xfiPrice = _price;
        prices["XFI"] = _price;
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
        return (validatorAPR, apyAmount);
    }

    function setDIAOracle(address) external {}

    function setFallbackOracle(address) external {}

    function isOracleFresh() external view returns (bool) {
        return isFresh;
    }
    
    function getPrice(string calldata symbol) external view returns (uint256) {
        return prices[symbol];
    }
    
    function getTotalStakedXFI() external view returns (uint256) {
        return totalStakedXFI;
    }
    
    /**
     * @dev Get APY for staking
     */
    function getCurrentAPY() external view returns (uint256) {
        return apyAmount;
    }
    
    /**
     * @dev Get APR for staking
     */
    function getCurrentAPR() external view returns (uint256) {
        return _currentAPR;
    }
    
    function getValidatorAPR() external view returns (uint256) {
        return validatorAPR;
    }
    
    function getUnbondingPeriod() external view returns (uint256) {
        return unbondingPeriod;
    }
    
    function setTotalStakedXFI(uint256 _amount) external {
        totalStakedXFI = _amount;
    }
    
    function setAPY(uint256 _apy) external {
        apyAmount = _apy;
    }
    
    function setValidatorAPR(uint256 _apr) external {
        validatorAPR = _apr;
        _currentAPR = _apr;
    }
    
    function setUnbondingPeriod(uint256 _period) external {
        unbondingPeriod = _period;
    }
    
    function setPrice(string calldata symbol, uint256 _price) external {
        prices[symbol] = _price;
    }
} 