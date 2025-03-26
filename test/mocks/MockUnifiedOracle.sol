// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/interfaces/IUnifiedOracle.sol";
import "../../src/interfaces/IOracle.sol";

contract MockUnifiedOracle is IUnifiedOracle, IOracle {
    mapping(address => uint256) private _userClaimableRewards;
    uint256 private _price;
    uint256 private _timestamp;
    uint256 private _apr;
    uint256 private _apy;
    uint256 private _totalStaked;
    uint256 private _validatorApr;
    uint256 private _unbondingPeriod;
    
    constructor() {
        _price = 1 ether;
        _timestamp = block.timestamp;
        _apr = 10 * 1e16; // 10%
        _apy = 8 * 1e16;  // 8%
        _totalStaked = 1000000 ether;
        _validatorApr = 12 * 1e16; // 12%
        _unbondingPeriod = 14 days;
    }
    
    function addUserClaimableRewards(address user, uint256 amount) external override(IUnifiedOracle) {
        _userClaimableRewards[user] += amount;
    }
    
    function getUserClaimableRewards(address user) external view override(IOracle, IUnifiedOracle) returns (uint256) {
        return _userClaimableRewards[user];
    }
    
    function clearUserClaimableRewards(address user) external override(IOracle) returns (uint256) {
        uint256 amount = _userClaimableRewards[user];
        _userClaimableRewards[user] = 0;
        return amount;
    }
    
    function decreaseUserClaimableRewards(address user, uint256 amount) external override(IOracle) returns (uint256) {
        if (_userClaimableRewards[user] < amount) {
            _userClaimableRewards[user] = 0;
        } else {
            _userClaimableRewards[user] -= amount;
        }
        return _userClaimableRewards[user];
    }
    
    function getPrice(string memory) external view override(IOracle, IUnifiedOracle) returns (uint256) {
        return _price;
    }
    
    function getCurrentAPR() external view override(IOracle, IUnifiedOracle) returns (uint256) {
        return _apr;
    }
    
    function getUnbondingPeriod() external view override(IOracle, IUnifiedOracle) returns (uint256) {
        return _unbondingPeriod;
    }
    
    function getXFIPrice() external view override(IUnifiedOracle) returns (uint256 price, uint256 timestamp) {
        return (_price, _timestamp);
    }
    
    function getCurrentRewards() external view override(IUnifiedOracle) returns (uint256 apr, uint256 apy) {
        return (_apr, _apy);
    }
    
    function getTotalStakedXFI() external view override(IOracle, IUnifiedOracle) returns (uint256) {
        return _totalStaked;
    }
    
    function getCurrentAPY() external view override(IOracle, IUnifiedOracle) returns (uint256) {
        return _apy;
    }
    
    function getValidatorAPR() external view override(IUnifiedOracle) returns (uint256) {
        return _validatorApr;
    }
    
    function isOracleFresh() external view override(IUnifiedOracle) returns (bool) {
        return (block.timestamp - _timestamp) <= 1 hours;
    }
    
    function setDIAOracle(address) external override(IUnifiedOracle) {}
    
    function setFallbackOracle(address) external override(IUnifiedOracle) {}
    
    function convertXFItoMPX(uint256 xfiAmount) external view override(IOracle, IUnifiedOracle) returns (uint256) {
        return xfiAmount;
    }
    
    // Additional IOracle functions
    function isValidatorActive(string calldata) external pure override(IOracle) returns (bool) {
        return true;
    }
    
    function getMPXPrice() external pure override(IOracle) returns (uint256) {
        return 4 * 1e16; // $0.04 with 18 decimals
    }
    
    function getValidatorAPR(string calldata) external view override(IOracle) returns (uint256) {
        return _validatorApr;
    }
    
    // Mock setter functions for testing
    function setPrice(uint256 price) external {
        _price = price;
        _timestamp = block.timestamp;
    }
    
    function setAPR(uint256 apr) external {
        _apr = apr;
    }
    
    function setAPY(uint256 apy) external {
        _apy = apy;
    }
    
    function setTotalStaked(uint256 totalStaked) external {
        _totalStaked = totalStaked;
    }
    
    function setValidatorAPR(uint256 validatorApr) external {
        _validatorApr = validatorApr;
    }
    
    function setUnbondingPeriod(uint256 period) external {
        _unbondingPeriod = period;
    }
    
    function updateAPR(uint256 apr) external override(IUnifiedOracle) {
        _apr = apr;
    }
    
    function updateAPY(uint256 apy) external override(IUnifiedOracle) {
        _apy = apy;
    }
    
    function updateTotalStakedXFI(uint256 amount) external override(IUnifiedOracle) {
        _totalStaked = amount;
    }
    
    function updateValidatorAPR(uint256 apr) external override(IUnifiedOracle) {
        _validatorApr = apr;
    }
} 