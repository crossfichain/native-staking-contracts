// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IUnifiedOracle} from "../../src/interfaces/IUnifiedOracle.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";

contract MockUnifiedOracle is IUnifiedOracle, IOracle {
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
    bool private _isUnstakingFrozen = false;
    mapping(address => uint256) private _userClaimableRewards;
    uint256 private constant MPX_PRICE_USD = 4 * 1e16; // $0.04 fixed price with 18 decimals
    
    // Role-based access control mocking
    mapping(bytes32 => mapping(address => bool)) private _roles;
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    event PriceSet(uint256 price);
    event RewardsSet(uint256 rewards);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    constructor() {
        lastUpdateTimestamp = block.timestamp;
        xfiPrice = 1 ether; // 1 USD in 18 decimals
        apyAmount = 8 * 1e16; // 8% in 18 decimals
        validatorAPR = 10 * 1e16; // 10% in 18 decimals
        unbondingPeriod = 14 days;
        totalStakedXFI = 1000000 ether;
        prices["XFI"] = 1 ether;
        _currentAPR = validatorAPR;
        
        // Grant the deployer the admin role
        _roles[DEFAULT_ADMIN_ROLE][msg.sender] = true;
    }
    
    // Mock AccessControl functions
    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _roles[role][account];
    }
    
    function grantRole(bytes32 role, address account) external {
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }
    
    function revokeRole(bytes32 role, address account) external {
        _roles[role][account] = false;
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

    function getXFIPrice() external view override returns (uint256, uint256) {
        return (xfiPrice, lastUpdateTimestamp);
    }

    function getCurrentRewards() external view override returns (uint256, uint256) {
        return (validatorAPR, apyAmount);
    }

    function setDIAOracle(address) external override {
        // No-op for mock
    }

    function setFallbackOracle(address) external override {
        // No-op for mock
    }

    function isOracleFresh() external view override returns (bool) {
        return isFresh;
    }
    
    function getPrice(string calldata symbol) external view override(IOracle, IUnifiedOracle) returns (uint256) {
        return prices[symbol];
    }
    
    function getTotalStakedXFI() external view override(IOracle, IUnifiedOracle) returns (uint256) {
        return totalStakedXFI;
    }
    
    /**
     * @dev Get APY for staking
     */
    function getCurrentAPY() external view override(IOracle, IUnifiedOracle) returns (uint256) {
        return apyAmount;
    }
    
    /**
     * @dev Get APR for staking
     */
    function getCurrentAPR() external view override(IOracle, IUnifiedOracle) returns (uint256) {
        return _currentAPR;
    }
    
    function getValidatorAPR() external view override returns (uint256) {
        return validatorAPR;
    }
    
    /**
     * @dev IOracle implementation of getValidatorAPR with parameter
     */
    function getValidatorAPR(string calldata) external view override returns (uint256) {
        return validatorAPR;
    }
    
    function getUnbondingPeriod() external view override(IOracle, IUnifiedOracle) returns (uint256) {
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
    
    /**
     * @dev Checks if unstaking is frozen (for testing purposes)
     * @return True if unstaking is frozen, false otherwise
     */
    function isUnstakingFrozen() external view override returns (bool) {
        return _isUnstakingFrozen;
    }
    
    /**
     * @dev Sets the unstaking frozen status for testing
     * @param frozen True to set unstaking as frozen, false otherwise
     */
    function setUnstakingFrozen(bool frozen) external {
        _isUnstakingFrozen = frozen;
    }
    
    /**
     * @dev Sets claimable rewards for a specific user (for testing)
     * @param user The user address
     * @param amount The reward amount to set
     */
    function setUserClaimableRewards(address user, uint256 amount) external {
        _userClaimableRewards[user] = amount;
    }
    
    /**
     * @dev Gets claimable rewards for a specific user
     * @param user The user address
     * @return The claimable reward amount
     */
    function getUserClaimableRewards(address user) external view override returns (uint256) {
        return _userClaimableRewards[user];
    }
    
    /**
     * @dev Clears claimable rewards for a user
     * @param user The user address
     * @return amount The amount that was cleared
     */
    function clearUserClaimableRewards(address user) external override returns (uint256 amount) {
        amount = _userClaimableRewards[user];
        _userClaimableRewards[user] = 0;
        return amount;
    }
    
    /**
     * @dev Decreases claimable rewards for a user
     * @param user The user address
     * @param amount The amount to decrease by
     * @return newAmount The new reward amount
     */
    function decreaseUserClaimableRewards(address user, uint256 amount) external override returns (uint256 newAmount) {
        if (_userClaimableRewards[user] < amount) {
            _userClaimableRewards[user] = 0;
        } else {
            _userClaimableRewards[user] -= amount;
        }
        return _userClaimableRewards[user];
    }
    
    /**
     * @dev IOracle implementation - checks if a validator is active
     */
    function isValidatorActive(string calldata) external pure override returns (bool) {
        return true;
    }
    
    /**
     * @dev IOracle implementation - returns the fixed price of MPX
     */
    function getMPXPrice() external pure override returns (uint256) {
        return MPX_PRICE_USD; // $0.04 with 18 decimals
    }
    
    /**
     * @dev IOracle implementation - converts XFI to MPX
     */
    function convertXFItoMPX(uint256 xfiAmount) external view override returns (uint256 mpxAmount) {
        // Using the fixed price of MPX to convert (assuming XFI price is 1 USD)
        return xfiAmount * xfiPrice / MPX_PRICE_USD;
    }
} 