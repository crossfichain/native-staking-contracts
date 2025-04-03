// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../../src/interfaces/IOracle.sol";

contract MockUnifiedOracle is IOracle {
    uint256 private _xfiPrice;
    uint256 private _mpxPrice;
    uint256 private _totalStakedXFI;
    uint256 private _currentAPY;
    uint256 private _currentAPR;
    uint256 private _unbondingPeriod;
    mapping(address => uint256) private _userClaimableRewards;
    mapping(address => mapping(string => uint256)) private _userValidatorClaimableRewards;
    mapping(address => mapping(string => uint256)) private _validatorStakes;
    uint256 private _launchTimestamp = block.timestamp;

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

    function getPrice(string calldata symbol) external view override returns (uint256) {
        if (keccak256(bytes(symbol)) == keccak256(bytes("XFI"))) {
            return _xfiPrice;
        } else if (keccak256(bytes(symbol)) == keccak256(bytes("MPX"))) {
            return _mpxPrice;
        }
        revert("Invalid symbol");
    }

    function isValidatorActive(string calldata) external view override returns (bool) {
        return true;
    }

    function getTotalStakedXFI() external view override returns (uint256) {
        return _totalStakedXFI;
    }

    function getValidatorAPR(string calldata) external view override returns (uint256) {
        return _currentAPR;
    }

    function getCurrentAPY() external view override returns (uint256) {
        return _currentAPY;
    }

    function getCurrentAPR() external view override returns (uint256) {
        return _currentAPR;
    }

    function getUnbondingPeriod() external view override returns (uint256) {
        return _unbondingPeriod;
    }

    function getMPXPrice() external pure override returns (uint256) {
        return 4 * 1e16; // $0.04 with 18 decimals
    }

    function convertXFItoMPX(uint256 xfiAmount) external view override returns (uint256 mpxAmount) {
        return (xfiAmount * _xfiPrice) / _mpxPrice;
    }

    function getUserClaimableRewards(address user) external view override returns (uint256) {
        return _userClaimableRewards[user];
    }

    function clearUserClaimableRewards(address user) external override returns (uint256 amount) {
        amount = _userClaimableRewards[user];
        _userClaimableRewards[user] = 0;
        return amount;
    }

    function decreaseUserClaimableRewards(address user, uint256 amount) external override returns (uint256 newAmount) {
        require(_userClaimableRewards[user] >= amount, "Insufficient rewards");
        _userClaimableRewards[user] -= amount;
        return _userClaimableRewards[user];
    }

    function getUserClaimableRewardsForValidator(address user, string calldata validator) external view override returns (uint256) {
        return _userValidatorClaimableRewards[user][validator];
    }

    function clearUserClaimableRewardsForValidator(address user, string calldata validator) external override returns (uint256) {
        uint256 amount = _userValidatorClaimableRewards[user][validator];
        _userValidatorClaimableRewards[user][validator] = 0;
        return amount;
    }

    function clearUserClaimableRewardsForValidator(
        address user,
        string calldata validator,
        uint256 amount
    ) external override returns (uint256) {
        require(_userValidatorClaimableRewards[user][validator] >= amount, "Amount exceeds available rewards");
        _userValidatorClaimableRewards[user][validator] -= amount;
        return amount;
    }

    function getValidatorStake(address user, string calldata validator) 
        external 
        view 
        returns (uint256) 
    {
        return _validatorStakes[user][validator];
    }

    function getTotalClaimableRewards() external view override returns (uint256) {
        return 1000 ether; // Example value
    }

    function getValidatorUnbondingPeriod(string calldata validator) external view returns (uint256) {
        return 86400; // 1 day in seconds
    }

    /**
     * @dev Sets the validator stake for a user
     * @param user The user whose stake is being updated
     * @param validator The validator ID 
     * @param amount The new stake amount
     */
    function setValidatorStake(address user, string calldata validator, uint256 amount) external {
        // Mock implementation - no actual storage
    }

    function setLaunchTimestamp(uint256 timestamp) external {
        _launchTimestamp = timestamp;
    }

    function getLaunchTimestamp() external view override returns (uint256) {
        return _launchTimestamp;
    }
} 