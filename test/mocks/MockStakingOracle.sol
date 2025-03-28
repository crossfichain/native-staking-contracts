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
    mapping(address => mapping(string => uint256)) private _userValidatorStakes;
    mapping(address => mapping(bytes => uint256)) private _userUnstakes;

    function getPrice(string calldata symbol) external view returns (uint256) {
        if (keccak256(bytes(symbol)) == keccak256(bytes("XFI"))) {
            return _xfiPrice;
        }
        return _mpxPrice;
    }

    function isValidatorActive(string calldata validator) external view returns (bool) {
        if (bytes(validator).length > 0 && _validatorActive[validator]) {
            return true;
        }
        // Default to true for backward compatibility
        return true;
    }

    function getTotalStakedXFI() external view returns (uint256) {
        return _totalStakedXFI;
    }

    function getValidatorAPR(string calldata validator) external view returns (uint256) {
        if (_validatorAPRs[validator] > 0) {
            return _validatorAPRs[validator];
        }
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

    function getValidatorStake(address user, string calldata validator) 
        external 
        view 
        returns (uint256) 
    {
        return _userValidatorStakes[user][validator];
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

    /**
     * @dev Sets the validator stake for a user
     * @param user The user whose stake is being updated
     * @param validator The validator ID 
     * @param amount The new stake amount
     */
    function setValidatorStake(address user, string calldata validator, uint256 amount) external {
        _userValidatorStakes[user][validator] = amount;
    }

    function setUserUnstake(address user, bytes calldata requestId, uint256 amount) external {
        _userUnstakes[user][requestId] = amount;
    }

    function getUserUnstake(address user, bytes calldata requestId) external view returns (uint256) {
        return _userUnstakes[user][requestId];
    }
    
    function clearUserUnstake(address user, bytes calldata requestId) external returns (uint256) {
        uint256 amount = _userUnstakes[user][requestId];
        _userUnstakes[user][requestId] = 0;
        return amount;
    }

    function getTotalClaimableRewards() external view returns (uint256) {
        // This is a mock, so we return a hardcoded value or sum of all rewards
        return 1000 ether; // Example value
    }

    // Map to store validator-specific APRs
    mapping(string => uint256) private _validatorAPRs;
    
    function setValidatorAPR(string calldata validator, uint256 apr) external {
        _validatorAPRs[validator] = apr;
    }

    // Map to store validator active status
    mapping(string => bool) private _validatorActive;
    
    function setIsValidatorActive(string calldata validator, bool active) external {
        _validatorActive[validator] = active;
    }

    // Map to store validator-specific unbonding periods
    mapping(string => uint256) private _validatorUnbondingPeriods;
    
    function setValidatorUnbondingPeriod(string calldata validator, uint256 period) external {
        _validatorUnbondingPeriods[validator] = period;
    }
    
    // Implement the getValidatorUnbondingPeriod function
    function getValidatorUnbondingPeriod(string calldata validator) external view returns (uint256) {
        if (_validatorUnbondingPeriods[validator] > 0) {
            return _validatorUnbondingPeriods[validator];
        }
        return _unbondingPeriod;
    }
} 