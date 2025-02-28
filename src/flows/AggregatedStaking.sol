// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractStakingFlow} from "../abstract/AbstractStakingFlow.sol";
import {IStakingManager} from "../interfaces/IStakingManager.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title AggregatedStaking
 * @notice Implementation of the aggregated staking flow
 * @dev Handles first flow where backend is single gateway summarizing all XFI
 */
contract AggregatedStaking is AbstractStakingFlow {
    using Math for uint256;

    // ============ State Variables ============
    
    // User data
    mapping(address => UserInfo) private _userInfo;
    
    // Reward pool
    uint256 private _rewardPool;
    uint256 private _lastCompoundTimestamp;
    
    // Share price tracking
    uint256 private _initialSharePrice;
    uint256 private _currentSharePrice;
    
    struct UserInfo {
        uint256 shares;              // User's share of the pool
        uint256 stakedAmount;        // Amount of tokens staked
        uint256 lastRewardClaim;     // Last reward claim timestamp
        bool isActive;               // Whether user is active in this flow
    }
    
    // ============ Events ============
    event SharePriceUpdated(uint256 oldPrice, uint256 newPrice);
    event UserAdded(address indexed user);
    event UserRemoved(address indexed user);
    
    // ============ Constructor ============
    constructor(address _manager) AbstractStakingFlow(_manager) {
        _lastCompoundTimestamp = block.timestamp;
        _initialSharePrice = PRECISION; // 1.0 in fixed point
        _currentSharePrice = PRECISION; // 1.0 in fixed point
    }
    
    // ============ External Functions ============
    
    /// @inheritdoc AbstractStakingFlow
    function stake(
        address user, 
        uint256 amount, 
        address /* validator - ignored in aggregated flow */
    ) external override onlyManager nonReentrant whenNotPaused returns (uint256 shares) {
        // Calculate shares based on current share price
        shares = calculateShares(amount);
        require(shares > 0, "AggregatedStaking: Zero shares");
        
        // Update user info
        UserInfo storage userInfo = _userInfo[user];
        
        if (!userInfo.isActive) {
            userInfo.isActive = true;
            userInfo.lastRewardClaim = block.timestamp;
            _usersCount++;
            emit UserAdded(user);
        }
        
        userInfo.shares += shares;
        userInfo.stakedAmount += amount;
        
        // Update totals
        _totalShares += shares;
        _totalStaked += amount;
        
        return shares;
    }
    
    /// @inheritdoc AbstractStakingFlow
    function unstake(
        address user, 
        uint256 amount, 
        address /* validator - ignored in aggregated flow */
    ) external override onlyManager nonReentrant returns (uint256 shares, uint256 rewards) {
        UserInfo storage userInfo = _userInfo[user];
        require(userInfo.isActive, "AggregatedStaking: User not active");
        require(userInfo.stakedAmount >= amount, "AggregatedStaking: Insufficient stake");
        
        // Calculate rewards
        rewards = calculateRewards(user, address(0));
        
        // Calculate shares to burn
        shares = amount.mulDiv(_totalShares, _totalStaked, Math.Rounding.Ceil);
        require(userInfo.shares >= shares, "AggregatedStaking: Insufficient shares");
        
        // Update user info
        userInfo.shares -= shares;
        userInfo.stakedAmount -= amount;
        userInfo.lastRewardClaim = block.timestamp;
        
        // Update totals
        _totalShares -= shares;
        _totalStaked -= amount;
        if (rewards > 0) {
            _rewardPool -= rewards;
        }
        
        // Check if user has unstaked everything
        if (userInfo.shares == 0) {
            userInfo.isActive = false;
            _usersCount--;
            emit UserRemoved(user);
        }
        
        return (shares, rewards);
    }
    
    /// @inheritdoc AbstractStakingFlow
    function claimRewards(
        address user,
        address /* validator - ignored in aggregated flow */
    ) external override onlyManager nonReentrant returns (uint256 rewards) {
        UserInfo storage userInfo = _userInfo[user];
        require(userInfo.isActive, "AggregatedStaking: User not active");
        
        rewards = calculateRewards(user, address(0));
        require(rewards > 0, "AggregatedStaking: No rewards");
        
        userInfo.lastRewardClaim = block.timestamp;
        _rewardPool -= rewards;
        
        return rewards;
    }
    
    /// @inheritdoc AbstractStakingFlow
    function addRewards(
        uint256 amount,
        address /* validator - ignored in aggregated flow */
    ) external override onlyManager nonReentrant payable {
        require(amount > 0, "AggregatedStaking: Zero amount");
        require(msg.value == amount, "AggregatedStaking: Incorrect value");
        
        _rewardPool += amount;
        
        // Update share price if there are users staked
        if (_totalShares > 0) {
            uint256 oldSharePrice = _currentSharePrice;
            
            // New share price calculation: (totalStaked + rewardPool) / totalShares * PRECISION
            uint256 newSharePrice = (_totalStaked + _rewardPool).mulDiv(
                PRECISION,
                _totalShares,
                Math.Rounding.Floor
            );
            
            _currentSharePrice = newSharePrice;
            _lastCompoundTimestamp = block.timestamp;
            
            emit SharePriceUpdated(oldSharePrice, newSharePrice);
        }
    }
    
    /// @inheritdoc AbstractStakingFlow
    function migrateUser(
        address user,
        bytes calldata /* stakingData - not used in this implementation */
    ) external override onlyManager nonReentrant returns (bytes memory) {
        UserInfo storage userInfo = _userInfo[user];
        require(userInfo.isActive, "AggregatedStaking: User not active");
        
        // Pack user's data for the migration
        bytes memory userData = abi.encode(
            userInfo.shares,
            userInfo.stakedAmount,
            calculateRewards(user, address(0))
        );
        
        // Reset user data in this flow
        if (userInfo.shares > 0) {
            _totalShares -= userInfo.shares;
        }
        
        if (userInfo.stakedAmount > 0) {
            _totalStaked -= userInfo.stakedAmount;
        }
        
        delete _userInfo[user];
        _usersCount--;
        
        emit UserRemoved(user);
        
        return userData;
    }
    
    // ============ View Functions ============
    
    /// @inheritdoc AbstractStakingFlow
    function calculateShares(uint256 amount) public view override returns (uint256) {
        if (_totalStaked == 0 || _totalShares == 0) {
            return amount;
        }
        
        return amount.mulDiv(
            _totalShares,
            _totalStaked,
            Math.Rounding.Floor
        );
    }
    
    /// @inheritdoc AbstractStakingFlow
    function calculateAmount(uint256 shares) public view override returns (uint256) {
        if (_totalShares == 0) {
            return shares;
        }
        
        return shares.mulDiv(
            _totalStaked,
            _totalShares,
            Math.Rounding.Floor
        );
    }
    
    /// @inheritdoc AbstractStakingFlow
    function calculateRewards(
        address user,
        address /* validator - ignored in aggregated flow */
    ) public view override returns (uint256) {
        UserInfo storage userInfo = _userInfo[user];
        if (!userInfo.isActive || userInfo.shares == 0 || _rewardPool == 0) {
            return 0;
        }
        
        return userInfo.shares.mulDiv(
            _rewardPool,
            _totalShares,
            Math.Rounding.Floor
        );
    }
    
    /// @notice Get user info
    /// @param user Address of the user
    /// @return Shares, staked amount, and last claim timestamp
    function getUserInfo(address user) external view returns (
        uint256 shares,
        uint256 stakedAmount,
        uint256 lastRewardClaim,
        bool isActive
    ) {
        UserInfo storage userInfo = _userInfo[user];
        return (
            userInfo.shares,
            userInfo.stakedAmount,
            userInfo.lastRewardClaim,
            userInfo.isActive
        );
    }
    
    /// @notice Get current share price
    /// @return Current share price in fixed point format (PRECISION = 1.0)
    function getCurrentSharePrice() external view returns (uint256) {
        return _currentSharePrice;
    }
    
    /// @notice Get reward pool
    /// @return Current reward pool size
    function getRewardPool() external view returns (uint256) {
        return _rewardPool;
    }
    
    /// @notice Get last compound timestamp
    /// @return Timestamp of the last reward compounding
    function getLastCompoundTimestamp() external view returns (uint256) {
        return _lastCompoundTimestamp;
    }
} 