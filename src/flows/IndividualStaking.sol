// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractStakingFlow} from "../abstract/AbstractStakingFlow.sol";
import {IStakingManager} from "../interfaces/IStakingManager.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title IndividualStaking
 * @notice Implementation of the individual staking flow
 * @dev Handles second flow where backend launches addresses for each position
 */
contract IndividualStaking is AbstractStakingFlow {
    using Math for uint256;
    
    // ============ Constants ============
    uint256 private constant MAX_VALIDATORS_PER_USER = 5;
    
    // ============ State Variables ============
    
    // User data
    mapping(address => UserInfo) private _userInfo;
    
    // Validator data
    mapping(address => ValidatorInfo) private _validatorInfo;
    address[] private _activeValidators;
    
    struct UserInfo {
        uint256 totalShares;         // Total user shares across all validators
        uint256 totalStaked;         // Total amount staked by user
        uint256 lastRewardClaim;     // Last reward claim timestamp
        bool isActive;               // Whether user is active in this flow
        
        // Mapping from validator address to user's stake with that validator
        mapping(address => ValidatorStake) validatorStakes;
        // List of validators user is staking with
        address[] validators;
    }
    
    struct ValidatorInfo {
        uint256 totalShares;         // Total shares for this validator
        uint256 totalStaked;         // Total amount staked with this validator
        uint256 rewardPool;          // Rewards allocated to this validator
        uint256 lastUpdateTime;      // Last reward update timestamp
        bool isActive;               // Whether validator is active
    }
    
    struct ValidatorStake {
        uint256 shares;              // User's share with this validator
        uint256 stakedAmount;        // Amount staked with this validator
        uint256 lastRewardClaim;     // Last reward claim from this validator
        bool isActive;               // Whether user is staking with this validator
    }
    
    // ============ Events ============
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event UserAddedToValidator(address indexed user, address indexed validator);
    event UserRemovedFromValidator(address indexed user, address indexed validator);
    event ValidatorRewardAdded(address indexed validator, uint256 amount);
    
    // ============ Constructor ============
    constructor(address _manager) AbstractStakingFlow(_manager) {}
    
    // ============ External Functions ============
    
    /// @inheritdoc AbstractStakingFlow
    function stake(
        address user, 
        uint256 amount, 
        address validator
    ) external override onlyManager nonReentrant whenNotPaused returns (uint256 shares) {
        require(validator != address(0), "IndividualStaking: Zero validator address");
        
        ValidatorInfo storage validatorInfo = _validatorInfo[validator];
        require(validatorInfo.isActive, "IndividualStaking: Validator not active");
        
        // Update user info
        UserInfo storage userInfo = _userInfo[user];
        
        // If new user to this flow
        if (!userInfo.isActive) {
            userInfo.isActive = true;
            userInfo.lastRewardClaim = block.timestamp;
            _usersCount++;
        }
        
        // Check if user already has this validator
        bool hasValidator = false;
        for (uint256 i = 0; i < userInfo.validators.length; i++) {
            if (userInfo.validators[i] == validator) {
                hasValidator = true;
                break;
            }
        }
        
        // If not, add validator to user's list
        if (!hasValidator) {
            require(userInfo.validators.length < MAX_VALIDATORS_PER_USER, "IndividualStaking: Too many validators");
            userInfo.validators.push(validator);
            userInfo.validatorStakes[validator].lastRewardClaim = block.timestamp;
            userInfo.validatorStakes[validator].isActive = true;
            emit UserAddedToValidator(user, validator);
        }
        
        // Calculate shares based on validator's share price
        shares = _calculateValidatorShares(validator, amount);
        require(shares > 0, "IndividualStaking: Zero shares");
        
        // Update user's stake with this validator
        ValidatorStake storage validatorStake = userInfo.validatorStakes[validator];
        validatorStake.shares += shares;
        validatorStake.stakedAmount += amount;
        
        // Update user's totals
        userInfo.totalShares += shares;
        userInfo.totalStaked += amount;
        
        // Update validator totals
        validatorInfo.totalShares += shares;
        validatorInfo.totalStaked += amount;
        
        // Update flow totals
        _totalShares += shares;
        _totalStaked += amount;
        
        return shares;
    }
    
    /// @inheritdoc AbstractStakingFlow
    function unstake(
        address user, 
        uint256 amount, 
        address validator
    ) external override onlyManager nonReentrant returns (uint256 shares, uint256 rewards) {
        require(validator != address(0), "IndividualStaking: Zero validator address");
        
        UserInfo storage userInfo = _userInfo[user];
        require(userInfo.isActive, "IndividualStaking: User not active");
        
        ValidatorStake storage validatorStake = userInfo.validatorStakes[validator];
        require(validatorStake.isActive, "IndividualStaking: Not staked with validator");
        require(validatorStake.stakedAmount >= amount, "IndividualStaking: Insufficient stake");
        
        // Calculate rewards
        rewards = _calculateValidatorRewards(user, validator);
        
        // Calculate shares to burn
        ValidatorInfo storage validatorInfo = _validatorInfo[validator];
        shares = amount.mulDiv(validatorInfo.totalShares, validatorInfo.totalStaked, Math.Rounding.Ceil);
        require(validatorStake.shares >= shares, "IndividualStaking: Insufficient shares");
        
        // Update user's stake with this validator
        validatorStake.shares -= shares;
        validatorStake.stakedAmount -= amount;
        validatorStake.lastRewardClaim = block.timestamp;
        
        // Update user's totals
        userInfo.totalShares -= shares;
        userInfo.totalStaked -= amount;
        
        // Update validator totals
        validatorInfo.totalShares -= shares;
        validatorInfo.totalStaked -= amount;
        if (rewards > 0) {
            validatorInfo.rewardPool -= rewards;
        }
        
        // Update flow totals
        _totalShares -= shares;
        _totalStaked -= amount;
        
        // Check if user has unstaked everything from this validator
        if (validatorStake.shares == 0) {
            validatorStake.isActive = false;
            
            // Remove validator from user's list
            for (uint256 i = 0; i < userInfo.validators.length; i++) {
                if (userInfo.validators[i] == validator) {
                    // Replace with last element and pop
                    userInfo.validators[i] = userInfo.validators[userInfo.validators.length - 1];
                    userInfo.validators.pop();
                    emit UserRemovedFromValidator(user, validator);
                    break;
                }
            }
            
            // Check if user has unstaked from all validators
            if (userInfo.validators.length == 0) {
                userInfo.isActive = false;
                _usersCount--;
            }
        }
        
        return (shares, rewards);
    }
    
    /// @inheritdoc AbstractStakingFlow
    function claimRewards(
        address user,
        address validator
    ) external override onlyManager nonReentrant returns (uint256 rewards) {
        UserInfo storage userInfo = _userInfo[user];
        require(userInfo.isActive, "IndividualStaking: User not active");
        
        // If validator is specified, claim from that validator only
        if (validator != address(0)) {
            ValidatorStake storage validatorStake = userInfo.validatorStakes[validator];
            require(validatorStake.isActive, "IndividualStaking: Not staked with validator");
            
            rewards = _calculateValidatorRewards(user, validator);
            require(rewards > 0, "IndividualStaking: No rewards");
            
            ValidatorInfo storage validatorInfo = _validatorInfo[validator];
            validatorInfo.rewardPool -= rewards;
            validatorStake.lastRewardClaim = block.timestamp;
        }
        // If no validator specified, claim from all validators
        else {
            for (uint256 i = 0; i < userInfo.validators.length; i++) {
                address val = userInfo.validators[i];
                uint256 valRewards = _calculateValidatorRewards(user, val);
                
                if (valRewards > 0) {
                    ValidatorInfo storage validatorInfo = _validatorInfo[val];
                    validatorInfo.rewardPool -= valRewards;
                    userInfo.validatorStakes[val].lastRewardClaim = block.timestamp;
                    rewards += valRewards;
                }
            }
            
            require(rewards > 0, "IndividualStaking: No rewards");
        }
        
        userInfo.lastRewardClaim = block.timestamp;
        return rewards;
    }
    
    /// @inheritdoc AbstractStakingFlow
    function addRewards(
        uint256 amount,
        address validator
    ) external override onlyManager nonReentrant payable {
        require(amount > 0, "IndividualStaking: Zero amount");
        require(msg.value == amount, "IndividualStaking: Incorrect value");
        require(validator != address(0), "IndividualStaking: Zero validator address");
        
        ValidatorInfo storage validatorInfo = _validatorInfo[validator];
        require(validatorInfo.isActive, "IndividualStaking: Validator not active");
        
        validatorInfo.rewardPool += amount;
        validatorInfo.lastUpdateTime = block.timestamp;
        
        emit ValidatorRewardAdded(validator, amount);
    }
    
    /// @inheritdoc AbstractStakingFlow
    function migrateUser(
        address user,
        bytes calldata stakingData
    ) external override onlyManager nonReentrant returns (bytes memory) {
        UserInfo storage userInfo = _userInfo[user];
        require(userInfo.isActive, "IndividualStaking: User not active");
        
        // Pack user's data for the migration
        bytes memory userData = abi.encode(
            userInfo.totalShares,
            userInfo.totalStaked,
            userInfo.validators,
            calculateRewards(user, address(0))
        );
        
        // Reset user data in this flow
        // First, update all validators this user was staking with
        for (uint256 i = 0; i < userInfo.validators.length; i++) {
            address validator = userInfo.validators[i];
            ValidatorStake storage validatorStake = userInfo.validatorStakes[validator];
            
            if (validatorStake.shares > 0) {
                ValidatorInfo storage validatorInfo = _validatorInfo[validator];
                validatorInfo.totalShares -= validatorStake.shares;
                validatorInfo.totalStaked -= validatorStake.stakedAmount;
                
                emit UserRemovedFromValidator(user, validator);
            }
        }
        
        // Then update flow totals
        if (userInfo.totalShares > 0) {
            _totalShares -= userInfo.totalShares;
        }
        
        if (userInfo.totalStaked > 0) {
            _totalStaked -= userInfo.totalStaked;
        }
        
        // Finally delete the user's data
        delete _userInfo[user];
        _usersCount--;
        
        return userData;
    }
    
    // ============ Validator Management ============
    
    /// @notice Register a new validator
    /// @param validator Validator address
    function registerValidator(address validator) external onlyManager {
        require(validator != address(0), "IndividualStaking: Zero address");
        
        ValidatorInfo storage validatorInfo = _validatorInfo[validator];
        require(!validatorInfo.isActive, "IndividualStaking: Already registered");
        
        validatorInfo.isActive = true;
        validatorInfo.lastUpdateTime = block.timestamp;
        _activeValidators.push(validator);
        
        emit ValidatorAdded(validator);
    }
    
    /// @notice Deregister a validator
    /// @param validator Validator address
    function deregisterValidator(address validator) external onlyManager {
        ValidatorInfo storage validatorInfo = _validatorInfo[validator];
        require(validatorInfo.isActive, "IndividualStaking: Not registered");
        require(validatorInfo.totalStaked == 0, "IndividualStaking: Has stakes");
        
        validatorInfo.isActive = false;
        
        // Remove from active validators list
        for (uint256 i = 0; i < _activeValidators.length; i++) {
            if (_activeValidators[i] == validator) {
                _activeValidators[i] = _activeValidators[_activeValidators.length - 1];
                _activeValidators.pop();
                break;
            }
        }
        
        emit ValidatorRemoved(validator);
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
        address validator
    ) public view override returns (uint256) {
        UserInfo storage userInfo = _userInfo[user];
        if (!userInfo.isActive) {
            return 0;
        }
        
        // If validator is specified, calculate rewards for that validator only
        if (validator != address(0)) {
            return _calculateValidatorRewards(user, validator);
        }
        
        // Otherwise, calculate rewards across all validators
        uint256 totalRewards = 0;
        for (uint256 i = 0; i < userInfo.validators.length; i++) {
            totalRewards += _calculateValidatorRewards(user, userInfo.validators[i]);
        }
        
        return totalRewards;
    }
    
    /// @notice Calculate rewards for a user from a specific validator
    /// @param user User address
    /// @param validator Validator address
    /// @return Rewards amount
    function _calculateValidatorRewards(
        address user,
        address validator
    ) internal view returns (uint256) {
        UserInfo storage userInfo = _userInfo[user];
        ValidatorStake storage validatorStake = userInfo.validatorStakes[validator];
        
        if (!validatorStake.isActive || validatorStake.shares == 0) {
            return 0;
        }
        
        ValidatorInfo storage validatorInfo = _validatorInfo[validator];
        if (validatorInfo.rewardPool == 0 || validatorInfo.totalShares == 0) {
            return 0;
        }
        
        return validatorStake.shares.mulDiv(
            validatorInfo.rewardPool,
            validatorInfo.totalShares,
            Math.Rounding.Floor
        );
    }
    
    /// @notice Calculate shares for a specific validator
    /// @param validator Validator address
    /// @param amount Amount to convert to shares
    /// @return Number of shares
    function _calculateValidatorShares(
        address validator,
        uint256 amount
    ) internal view returns (uint256) {
        ValidatorInfo storage validatorInfo = _validatorInfo[validator];
        
        if (validatorInfo.totalStaked == 0 || validatorInfo.totalShares == 0) {
            return amount;
        }
        
        return amount.mulDiv(
            validatorInfo.totalShares,
            validatorInfo.totalStaked,
            Math.Rounding.Floor
        );
    }
    
    /// @notice Get user info
    /// @param user Address of the user
    /// @return totalShares Total shares across all validators
    /// @return totalStaked Total staked amount across all validators
    /// @return lastRewardClaim Last reward claim timestamp
    /// @return validators Array of validators user is staking with
    function getUserInfo(address user) external view returns (
        uint256 totalShares,
        uint256 totalStaked,
        uint256 lastRewardClaim,
        address[] memory validators
    ) {
        UserInfo storage userInfo = _userInfo[user];
        return (
            userInfo.totalShares,
            userInfo.totalStaked,
            userInfo.lastRewardClaim,
            userInfo.validators
        );
    }
    
    /// @notice Get user's stake with a specific validator
    /// @param user User address
    /// @param validator Validator address
    /// @return shares User's shares with this validator
    /// @return stakedAmount Amount staked with this validator
    /// @return lastRewardClaim Last reward claim timestamp
    /// @return isActive Whether user is actively staking with this validator
    function getUserValidatorStake(
        address user,
        address validator
    ) external view returns (
        uint256 shares,
        uint256 stakedAmount,
        uint256 lastRewardClaim,
        bool isActive
    ) {
        ValidatorStake storage validatorStake = _userInfo[user].validatorStakes[validator];
        return (
            validatorStake.shares,
            validatorStake.stakedAmount,
            validatorStake.lastRewardClaim,
            validatorStake.isActive
        );
    }
    
    /// @notice Get validator info
    /// @param validator Validator address
    /// @return totalShares Total shares for this validator
    /// @return totalStaked Total staked with this validator
    /// @return rewardPool Reward pool for this validator
    /// @return lastUpdateTime Last reward update timestamp
    /// @return isActive Whether validator is active
    function getValidatorInfo(
        address validator
    ) external view returns (
        uint256 totalShares,
        uint256 totalStaked,
        uint256 rewardPool,
        uint256 lastUpdateTime,
        bool isActive
    ) {
        ValidatorInfo storage validatorInfo = _validatorInfo[validator];
        return (
            validatorInfo.totalShares,
            validatorInfo.totalStaked,
            validatorInfo.rewardPool,
            validatorInfo.lastUpdateTime,
            validatorInfo.isActive
        );
    }
    
    /// @notice Get all active validators
    /// @return Array of active validator addresses
    function getActiveValidators() external view returns (address[] memory) {
        return _activeValidators;
    }
} 