// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/interfaces/IOracle.sol";

contract MockStakingOracle is IOracle {
    uint256 private _price;
    uint256 private _unbondingPeriod;
    bool private _isValidatorActive;
    uint256 private _totalStakedXFI;
    uint256 private _validatorAPR;
    uint256 private _currentAPY;
    uint256 private _currentAPR;
    uint256 private _mpxPrice;
    uint256 private _userClaimableRewards;

    function getPrice(string calldata symbol) external view returns (uint256) {
        return _price;
    }

    function setPrice(uint256 price) external {
        _price = price;
    }

    function isValidatorActive(string calldata validator) external view returns (bool) {
        return _isValidatorActive;
    }

    function setValidatorActive(bool active) external {
        _isValidatorActive = active;
    }

    function getTotalStakedXFI() external view returns (uint256) {
        return _totalStakedXFI;
    }

    function setTotalStakedXFI(uint256 amount) external {
        _totalStakedXFI = amount;
    }

    function getValidatorAPR(string calldata validator) external view returns (uint256) {
        return _validatorAPR;
    }

    function setValidatorAPR(uint256 apr) external {
        _validatorAPR = apr;
    }

    function getCurrentAPY() external view returns (uint256) {
        return _currentAPY;
    }

    function setCurrentAPY(uint256 apy) external {
        _currentAPY = apy;
    }

    function getCurrentAPR() external view returns (uint256) {
        return _currentAPR;
    }

    function setCurrentAPR(uint256 apr) external {
        _currentAPR = apr;
    }

    function getUnbondingPeriod() external view returns (uint256) {
        return _unbondingPeriod;
    }

    function setUnbondingPeriod(uint256 period) external {
        _unbondingPeriod = period;
    }

    function getMPXPrice() external pure returns (uint256) {
        return 1e18; // 1:1 price for testing
    }

    function setMPXPrice(uint256 price) external {
        _mpxPrice = price;
    }

    function convertXFItoMPX(uint256 amount) external view returns (uint256) {
        return amount;
    }

    function getUserClaimableRewards(address user) external view returns (uint256) {
        return _userClaimableRewards;
    }

    function setUserClaimableRewards(uint256 amount) external {
        _userClaimableRewards = amount;
    }

    function clearUserClaimableRewards(address user) external returns (uint256) {
        uint256 amount = _userClaimableRewards;
        _userClaimableRewards = 0;
        return amount;
    }

    function decreaseUserClaimableRewards(address user, uint256 amount) external returns (uint256) {
        if (_userClaimableRewards >= amount) {
            _userClaimableRewards -= amount;
        } else {
            _userClaimableRewards = 0;
        }
        return _userClaimableRewards;
    }
} 