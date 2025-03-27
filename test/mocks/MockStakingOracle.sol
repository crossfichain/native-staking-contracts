// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../interfaces/IOracle.sol";

contract MockStakingOracle is IOracle {
    uint256 private _xfiPrice;
    uint256 private _mpxPrice;
    mapping(address => uint256) private _userClaimableRewards;
    mapping(address => mapping(string => uint256)) private _userValidatorClaimableRewards;
    uint256 private _totalStakedXFI;
    uint256 private _currentAPY;
    uint256 private _currentAPR;
    uint256 private _unbondingPeriod;

    function getPrice(string calldata symbol) external view returns (uint256) {
        if (keccak256(bytes(symbol)) == keccak256(bytes("XFI"))) {
            return _xfiPrice;
        }
        return _mpxPrice;
    }

    function isValidatorActive(string calldata validator) external view returns (bool) {
        return true;
    }

    function getTotalStakedXFI() external view returns (uint256) {
        return _totalStakedXFI;
    }

    function getValidatorAPR(string calldata validator) external view returns (uint256) {
        return _currentAPR;
    }

    function getCurrentAPY() external view returns (uint256) {
        return _currentAPY;
    }

    function getCurrentAPR() external view returns (uint256) {
        return _currentAPR;
    }

    function getUnbondingPeriod() external view returns (uint256) {
        return _unbondingPeriod;
    }

    function getMPXPrice() external pure returns (uint256) {
        return 4 * 1e16; // $0.04
    }

    function convertXFItoMPX(uint256 amount) external view returns (uint256) {
        return (amount * _xfiPrice) / _mpxPrice;
    }

    function getUserClaimableRewards(address user) external view returns (uint256) {
        return _userClaimableRewards[user];
    }

    function clearUserClaimableRewards(address user) external returns (uint256) {
        uint256 amount = _userClaimableRewards[user];
        _userClaimableRewards[user] = 0;
        return amount;
    }

    function decreaseUserClaimableRewards(address user, uint256 amount) external returns (uint256) {
        if (_userClaimableRewards[user] >= amount) {
            _userClaimableRewards[user] -= amount;
        } else {
            _userClaimableRewards[user] = 0;
        }
        return _userClaimableRewards[user];
    }

    function getUserClaimableRewardsForValidator(address user, string calldata validator) 
        external 
        view 
        returns (uint256) 
    {
        return _userValidatorClaimableRewards[user][validator];
    }

    function clearUserClaimableRewardsForValidator(address user, string calldata validator) 
        external 
        returns (uint256) 
    {
        uint256 amount = _userValidatorClaimableRewards[user][validator];
        _userValidatorClaimableRewards[user][validator] = 0;
        return amount;
    }

    // Admin functions for testing
    function setXfiPrice(uint256 price) external {
        _xfiPrice = price;
    }

    function setMpxPrice(uint256 price) external {
        _mpxPrice = price;
    }

    function setTotalStakedXFI(uint256 amount) external {
        _totalStakedXFI = amount;
    }

    function setCurrentAPY(uint256 apy) external {
        _currentAPY = apy;
    }

    function setCurrentAPR(uint256 apr) external {
        _currentAPR = apr;
    }

    function setUnbondingPeriod(uint256 period) external {
        _unbondingPeriod = period;
    }

    function setUserClaimableRewards(address user, uint256 amount) external {
        _userClaimableRewards[user] = amount;
    }

    function setUserClaimableRewardsForValidator(address user, string calldata validator, uint256 amount) external {
        _userValidatorClaimableRewards[user][validator] = amount;
    }

    function setValidatorStake(address user, string calldata validator, uint256 amount) external {
        _totalStakedXFI += amount;
    }
} 