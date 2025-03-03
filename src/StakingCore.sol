// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IOracle} from "./interfaces/IOracle.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title StakingCore
 * @notice Core staking functionality with simplified architecture
 * @dev Handles staking positions and validator management with clear separation of concerns
 */
contract StakingCore is AccessControlEnumerable, ReentrancyGuard, Pausable {
    using Math for uint256;

    // ============ Constants ============
    uint256 private constant PRECISION = 1e18;
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MAX_COMMISSION = 3000; // 30% in basis points
    uint256 private constant MIN_STAKE_DEFAULT = 50 ether;
    uint256 private constant MAX_VALIDATORS_PER_USER = 5;
    uint256 private constant REWARD_CLAIM_COOLDOWN = 1 days;
    
    // ============ Roles ============
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    // ============ Types ============
    
    /// @notice Validator information
    struct Validator {
        address evmAddress;        // Validator address on EVM
        string cosmosAddress;      // Validator address on Cosmos
        string name;               // Human readable name
        uint256 commission;        // Commission rate in basis points
        uint256 totalStaked;       // Total tokens staked with this validator
        uint256 totalShares;       // Total shares for this validator
        uint256 rewardPool;        // Accumulated rewards for this validator
        uint256 lastUpdateTime;    // Last time rewards were updated
        bool isActive;             // Whether validator is active
    }
    
    /// @notice User staking position
    struct Position {
        uint256 totalStaked;       // Total staked by user
        uint256 totalShares;       // Total shares owned by user
        uint256 lastClaimTime;     // Last time rewards were claimed
        address[] validators;      // Validators user has staked with
        bool isActive;             // Whether position is active
    }
    
    /// @notice User-validator relationship
    struct UserValidatorStake {
        uint256 shares;            // Shares in this validator
        uint256 stakedAmount;      // Amount staked with this validator
        bool isActive;             // Whether stake is active
    }
    
    // ============ State Variables ============
    
    // Oracle
    IOracle public oracle;
    
    // Global counters
    uint256 public totalStaked;
    uint256 public totalShares;
    uint256 public userCount;
    uint256 public minimumStake;
    
    // Storage 
    mapping(address => Position) private positions;
    mapping(address => Validator) public validators;
    mapping(address => mapping(address => UserValidatorStake)) private userValidatorStakes;
    
    // Registry
    address[] public validatorsList;
    address[] public usersList;
    
    // ============ Events ============
    
    // System events
    event MinimumStakeUpdated(uint256 newMinimumStake);
    
    // Validator events
    event ValidatorRegistered(address indexed validatorAddress, string cosmosAddress, string name);
    event ValidatorUpdated(address indexed validatorAddress, string newCosmosAddress, string newName);
    event ValidatorActivated(address indexed validatorAddress);
    event ValidatorDeactivated(address indexed validatorAddress);
    event ValidatorCommissionUpdated(address indexed validatorAddress, uint256 newCommission);
    event ValidatorRewardsUpdated(address indexed validatorAddress, uint256 totalAmount);
    
    // User events
    event Staked(address indexed user, address indexed validator, uint256 amount, uint256 shares);
    event Unstaked(address indexed user, address indexed validator, uint256 amount, uint256 shares, uint256 rewards);
    event RewardsClaimed(address indexed user, address indexed validator, uint256 amount);
    event UserAdded(address indexed user);
    event UserRemoved(address indexed user);
    event RewardsReinvested(address indexed user, uint256 amount, uint256 shares);
    
    // ============ Constructor ============
    constructor(
        address _oracle,
        address _operator,
        address _emergency
    ) {
        require(_oracle != address(0), "StakingCore: Zero oracle address");
        oracle = IOracle(_oracle);
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, _operator);
        _grantRole(EMERGENCY_ROLE, _emergency);
        
        // Set default configuration
        minimumStake = MIN_STAKE_DEFAULT;
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Set minimum stake amount
     * @param newMinimumStake New minimum stake amount
     */
    function setMinimumStake(uint256 newMinimumStake) external onlyRole(OPERATOR_ROLE) {
        require(newMinimumStake > 0, "StakingCore: Zero minimum");
        minimumStake = newMinimumStake;
        emit MinimumStakeUpdated(newMinimumStake);
    }
    
    /**
     * @notice Register a new validator
     * @param validatorAddress EVM address of validator
     * @param cosmosAddress Cosmos address of validator
     * @param name Human-readable name of validator
     * @param commission Commission rate in basis points
     */
    function registerValidator(
        address validatorAddress,
        string calldata cosmosAddress,
        string calldata name,
        uint256 commission
    ) external onlyRole(OPERATOR_ROLE) {
        require(validatorAddress != address(0), "StakingCore: Zero address");
        require(bytes(cosmosAddress).length > 0, "StakingCore: Empty cosmos address");
        require(bytes(name).length > 0, "StakingCore: Empty name");
        require(commission <= MAX_COMMISSION, "StakingCore: Commission too high");
        
        Validator storage validator = validators[validatorAddress];
        require(!validator.isActive, "StakingCore: Already registered");
        
        // Register validator
        validator.evmAddress = validatorAddress;
        validator.cosmosAddress = cosmosAddress;
        validator.name = name;
        validator.commission = commission;
        validator.isActive = true;
        validator.lastUpdateTime = block.timestamp;
        
        validatorsList.push(validatorAddress);
        
        // Grant validator role
        _grantRole(VALIDATOR_ROLE, validatorAddress);
        
        emit ValidatorRegistered(validatorAddress, cosmosAddress, name);
    }
    
    /**
     * @notice Update validator information
     * @param validatorAddress Validator address to update
     * @param cosmosAddress New cosmos address
     * @param name New validator name
     */
    function updateValidator(
        address validatorAddress,
        string calldata cosmosAddress,
        string calldata name
    ) external onlyRole(OPERATOR_ROLE) {
        require(validatorAddress != address(0), "StakingCore: Zero address");
        
        Validator storage validator = validators[validatorAddress];
        require(validator.isActive, "StakingCore: Not registered");
        
        validator.cosmosAddress = cosmosAddress;
        validator.name = name;
        
        emit ValidatorUpdated(validatorAddress, cosmosAddress, name);
    }
    
    /**
     * @notice Set validator active status
     * @param validatorAddress Validator address to update
     * @param isActive New active status
     */
    function setValidatorStatus(
        address validatorAddress,
        bool isActive
    ) external onlyRole(OPERATOR_ROLE) {
        Validator storage validator = validators[validatorAddress];
        require(validator.evmAddress != address(0), "StakingCore: Not registered");
        
        // If deactivating, check that validator has no stakes
        if (!isActive && validator.isActive) {
            require(validator.totalStaked == 0, "StakingCore: Validator has stakes");
            emit ValidatorDeactivated(validatorAddress);
        }
        // If activating
        else if (isActive && !validator.isActive) {
            emit ValidatorActivated(validatorAddress);
        }
        
        validator.isActive = isActive;
    }
    
    /**
     * @notice Update validator commission rate
     * @param validatorAddress Validator address to update
     * @param commission New commission rate in basis points
     */
    function setValidatorCommission(
        address validatorAddress,
        uint256 commission
    ) external onlyRole(OPERATOR_ROLE) {
        require(commission <= MAX_COMMISSION, "StakingCore: Commission too high");
        
        Validator storage validator = validators[validatorAddress];
        require(validator.isActive, "StakingCore: Not registered");
        
        validator.commission = commission;
        
        emit ValidatorCommissionUpdated(validatorAddress, commission);
    }
    
    // ============ Operator Functions ============
    
    /**
     * @notice Update rewards for a specific validator
     * @param validatorAddress Validator address to update rewards for
     * @param rewardAmount Amount of rewards to add
     */
    function updateValidatorRewards(
        address validatorAddress,
        uint256 rewardAmount
    ) external payable onlyRole(OPERATOR_ROLE) {
        require(validatorAddress != address(0), "StakingCore: Zero address");
        require(msg.value == rewardAmount, "StakingCore: Incorrect value");
        
        Validator storage validator = validators[validatorAddress];
        require(validator.isActive, "StakingCore: Not registered");
        
        validator.rewardPool += rewardAmount;
        validator.lastUpdateTime = block.timestamp;
        
        emit ValidatorRewardsUpdated(validatorAddress, rewardAmount);
    }
    
    /**
     * @notice Emergency pause staking
     */
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }
    
    /**
     * @notice Resume staking
     */
    function unpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }
    
    // ============ User Functions ============
    
    /**
     * @notice Stake tokens with a validator
     * @param validatorAddress Validator to stake with
     */
    function stake(
        address validatorAddress
    ) external payable nonReentrant whenNotPaused {
        require(msg.value >= minimumStake, "StakingCore: Below minimum");
        
        // Validate validator
        Validator storage validator = validators[validatorAddress];
        require(validator.isActive, "StakingCore: Invalid validator");
        
        // Get or create user position
        Position storage position = positions[msg.sender];
        if (!position.isActive) {
            position.isActive = true;
            position.lastClaimTime = block.timestamp;
            usersList.push(msg.sender);
            userCount++;
            emit UserAdded(msg.sender);
        }
        
        // Check validator limit
        require(position.validators.length < MAX_VALIDATORS_PER_USER || 
                _hasValidator(position, validatorAddress), 
                "StakingCore: Too many validators");
        
        // Add validator to user's list if not already there
        if (!_hasValidator(position, validatorAddress)) {
            position.validators.push(validatorAddress);
        }
        
        // Calculate shares
        uint256 shares = _calculateShares(msg.value, validator.totalStaked, validator.totalShares);
        
        // Update user-validator stake
        UserValidatorStake storage userStake = userValidatorStakes[msg.sender][validatorAddress];
        userStake.shares += shares;
        userStake.stakedAmount += msg.value;
        userStake.isActive = true;
        
        // Update totals
        position.totalStaked += msg.value;
        position.totalShares += shares;
        validator.totalStaked += msg.value;
        validator.totalShares += shares;
        totalStaked += msg.value;
        totalShares += shares;
        
        emit Staked(msg.sender, validatorAddress, msg.value, shares);
    }
    
    /**
     * @notice Unstake tokens from a validator
     * @param amount Amount to unstake
     * @param validatorAddress Validator to unstake from
     */
    function unstake(
        uint256 amount,
        address validatorAddress
    ) external nonReentrant {
        // Validate request
        Position storage position = positions[msg.sender];
        require(position.isActive, "StakingCore: Not staked");
        require(_hasValidator(position, validatorAddress), "StakingCore: No stake with validator");
        
        Validator storage validator = validators[validatorAddress];
        UserValidatorStake storage userStake = userValidatorStakes[msg.sender][validatorAddress];
        
        require(userStake.stakedAmount >= amount, "StakingCore: Insufficient stake");
        
        // Calculate shares and rewards
        uint256 shares = amount.mulDiv(
            validator.totalShares,
            validator.totalStaked,
            Math.Rounding.Ceil
        );
        
        uint256 rewards = _calculateRewards(msg.sender, validatorAddress);
        
        // Update state
        userStake.shares -= shares;
        userStake.stakedAmount -= amount;
        
        position.totalStaked -= amount;
        position.totalShares -= shares;
        position.lastClaimTime = block.timestamp;
        
        validator.totalStaked -= amount;
        validator.totalShares -= shares;
        
        totalStaked -= amount;
        totalShares -= shares;
        
        // Remove validator from user's list if fully unstaked
        if (userStake.stakedAmount == 0) {
            userStake.isActive = false;
            _removeValidator(position, validatorAddress);
        }
        
        // Handle rewards
        if (rewards > 0) {
            validator.rewardPool -= rewards;
        }
        
        // Transfer tokens
        (bool success, ) = msg.sender.call{value: amount + rewards}("");
        require(success, "StakingCore: Transfer failed");
        
        // Remove user if no stakes left
        if (position.totalStaked == 0) {
            position.isActive = false;
            userCount--;
            emit UserRemoved(msg.sender);
        }
        
        emit Unstaked(msg.sender, validatorAddress, amount, shares, rewards);
    }
    
    /**
     * @notice Claim rewards from a validator
     * @param validatorAddress Validator to claim from
     * @return Amount of rewards claimed
     */
    function claimRewards(
        address validatorAddress
    ) external nonReentrant returns (uint256) {
        Position storage position = positions[msg.sender];
        require(position.isActive, "StakingCore: Not staked");
        
        // Check cooldown period
        require(
            block.timestamp >= position.lastClaimTime + REWARD_CLAIM_COOLDOWN,
            "StakingCore: Too soon to claim"
        );
        
        uint256 rewards;
        
        // If specific validator
        if (validatorAddress != address(0)) {
            require(_hasValidator(position, validatorAddress), "StakingCore: No stake with validator");
            
            rewards = _calculateRewards(msg.sender, validatorAddress);
            require(rewards > 0, "StakingCore: No rewards");
            
            // Update validator reward pool
            Validator storage validator = validators[validatorAddress];
            validator.rewardPool -= rewards;
        }
        // If claiming from all validators
        else {
            // Sum rewards from all validators
            for (uint256 i = 0; i < position.validators.length; i++) {
                address valAddr = position.validators[i];
                uint256 valRewards = _calculateRewards(msg.sender, valAddr);
                
                if (valRewards > 0) {
                    // Update validator reward pool
                    Validator storage validator = validators[valAddr];
                    validator.rewardPool -= valRewards;
                    rewards += valRewards;
                }
            }
            
            require(rewards > 0, "StakingCore: No rewards");
        }
        
        // Update last claim time
        position.lastClaimTime = block.timestamp;
        
        // Transfer rewards
        (bool success, ) = msg.sender.call{value: rewards}("");
        require(success, "StakingCore: Transfer failed");
        
        emit RewardsClaimed(msg.sender, validatorAddress, rewards);
        return rewards;
    }
    
    /**
     * @notice Claim and reinvest rewards with a validator
     * @param validatorAddress Validator to claim from and reinvest with
     * @return Amount of rewards reinvested
     */
    function claimAndReinvest(
        address validatorAddress
    ) external nonReentrant whenNotPaused returns (uint256) {
        Position storage position = positions[msg.sender];
        require(position.isActive, "StakingCore: Not staked");
        
        // Check cooldown period
        require(
            block.timestamp >= position.lastClaimTime + REWARD_CLAIM_COOLDOWN,
            "StakingCore: Too soon to claim"
        );
        
        uint256 rewards;
        address targetValidator = validatorAddress;
        
        // If specific validator
        if (validatorAddress != address(0)) {
            require(_hasValidator(position, validatorAddress), "StakingCore: No stake with validator");
            
            rewards = _calculateRewards(msg.sender, validatorAddress);
            require(rewards > 0, "StakingCore: No rewards");
            
            // Update validator reward pool
            Validator storage validator = validators[validatorAddress];
            validator.rewardPool -= rewards;
        }
        // If claiming from all validators
        else {
            // Sum rewards from all validators
            for (uint256 i = 0; i < position.validators.length; i++) {
                address valAddr = position.validators[i];
                uint256 valRewards = _calculateRewards(msg.sender, valAddr);
                
                if (valRewards > 0) {
                    // Update validator reward pool
                    Validator storage validator = validators[valAddr];
                    validator.rewardPool -= valRewards;
                    rewards += valRewards;
                    
                    // Use first validator with rewards as target if none specified
                    if (targetValidator == address(0)) {
                        targetValidator = valAddr;
                    }
                }
            }
            
            require(rewards > 0, "StakingCore: No rewards");
        }
        
        // Make sure we have a valid target validator
        require(targetValidator != address(0), "StakingCore: No valid validator");
        require(validators[targetValidator].isActive, "StakingCore: Inactive validator");
        
        // Reinvest rewards
        Validator storage targetVal = validators[targetValidator];
        
        // Calculate shares
        uint256 shares = _calculateShares(rewards, targetVal.totalStaked, targetVal.totalShares);
        
        // Update user-validator stake
        UserValidatorStake storage userStake = userValidatorStakes[msg.sender][targetValidator];
        userStake.shares += shares;
        userStake.stakedAmount += rewards;
        userStake.isActive = true;
        
        // Add validator to user's list if not already there
        if (!_hasValidator(position, targetValidator)) {
            position.validators.push(targetValidator);
        }
        
        // Update totals
        position.totalStaked += rewards;
        position.totalShares += shares;
        position.lastClaimTime = block.timestamp;
        
        targetVal.totalStaked += rewards;
        targetVal.totalShares += shares;
        
        totalStaked += rewards;
        totalShares += shares;
        
        emit Staked(msg.sender, targetValidator, rewards, shares);
        emit RewardsReinvested(msg.sender, rewards, shares);
        
        return rewards;
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get validator information
     * @param validatorAddress Validator address to query
     * @return evmAddress EVM address of validator
     * @return cosmosAddress Cosmos address of validator
     * @return name Validator name
     * @return commission Commission rate
     * @return totalStaked Total staked with validator
     * @return totalShares Total shares for validator
     * @return rewardPool Reward pool for validator
     * @return lastUpdateTime Last update time
     * @return isActive Whether validator is active
     */
    function getValidatorInfo(
        address validatorAddress
    ) external view returns (
        address evmAddress,
        string memory cosmosAddress,
        string memory name,
        uint256 commission,
        uint256 totalStaked,
        uint256 totalShares,
        uint256 rewardPool,
        uint256 lastUpdateTime,
        bool isActive
    ) {
        Validator storage validator = validators[validatorAddress];
        return (
            validator.evmAddress,
            validator.cosmosAddress,
            validator.name,
            validator.commission,
            validator.totalStaked,
            validator.totalShares,
            validator.rewardPool,
            validator.lastUpdateTime,
            validator.isActive
        );
    }
    
    /**
     * @notice Get user position
     * @param user User address
     * @return totalStaked Total staked by user
     * @return totalShares Total shares for user
     * @return pendingRewards Pending rewards for user
     * @return validatorCount Number of validators user is staked with
     */
    function getUserPosition(
        address user
    ) public view returns (
        uint256 totalStaked,
        uint256 totalShares,
        uint256 pendingRewards,
        uint256 validatorCount
    ) {
        Position storage position = positions[user];
        if (!position.isActive) {
            return (0, 0, 0, 0);
        }
        
        // Calculate total pending rewards
        uint256 rewards = 0;
        for (uint256 i = 0; i < position.validators.length; i++) {
            rewards += _calculateRewards(user, position.validators[i]);
        }
        
        return (
            position.totalStaked,
            position.totalShares,
            rewards,
            position.validators.length
        );
    }
    
    /**
     * @notice Get user's validator stakes
     * @param user User address
     * @return validators Array of validator addresses
     * @return stakedAmounts Array of staked amounts
     * @return shares Array of share amounts
     * @return rewards Array of pending rewards
     */
    function getUserValidators(
        address user
    ) external view returns (
        address[] memory validators,
        uint256[] memory stakedAmounts,
        uint256[] memory shares,
        uint256[] memory rewards
    ) {
        Position storage position = positions[user];
        if (!position.isActive || position.validators.length == 0) {
            return (new address[](0), new uint256[](0), new uint256[](0), new uint256[](0));
        }
        
        validators = position.validators;
        stakedAmounts = new uint256[](validators.length);
        shares = new uint256[](validators.length);
        rewards = new uint256[](validators.length);
        
        for (uint256 i = 0; i < validators.length; i++) {
            UserValidatorStake storage stake = userValidatorStakes[user][validators[i]];
            stakedAmounts[i] = stake.stakedAmount;
            shares[i] = stake.shares;
            rewards[i] = _calculateRewards(user, validators[i]);
        }
        
        return (validators, stakedAmounts, shares, rewards);
    }
    
    /**
     * @notice Get active validators
     * @return Array of active validator addresses
     */
    function getActiveValidators() external view returns (address[] memory) {
        uint256 activeCount = 0;
        
        // First, count active validators
        for (uint256 i = 0; i < validatorsList.length; i++) {
            if (validators[validatorsList[i]].isActive) {
                activeCount++;
            }
        }
        
        // Then, create and fill array
        address[] memory activeValidators = new address[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < validatorsList.length; i++) {
            if (validators[validatorsList[i]].isActive) {
                activeValidators[index] = validatorsList[i];
                index++;
            }
        }
        
        return activeValidators;
    }
    
    /**
     * @notice Get current APR from oracle
     * @return Current APR in basis points (10000 = 100%)
     */
    function getCurrentAPR() external view returns (uint256) {
        try oracle.getCurrentAPR() returns (uint256 apr) {
            return apr;
        } catch {
            return 0;
        }
    }
    
    /**
     * @notice Calculate pending rewards for a user-validator pair
     * @param user User address
     * @param validatorAddress Validator address
     * @return Pending rewards
     */
    function _calculateRewards(
        address user,
        address validatorAddress
    ) internal view returns (uint256) {
        UserValidatorStake storage stake = userValidatorStakes[user][validatorAddress];
        Validator storage validator = validators[validatorAddress];
        
        if (!stake.isActive || stake.shares == 0 || validator.rewardPool == 0) {
            return 0;
        }
        
        return stake.shares.mulDiv(
            validator.rewardPool,
            validator.totalShares,
            Math.Rounding.Floor
        );
    }
    
    /**
     * @notice Calculate shares based on amount
     * @param amount Amount to convert to shares
     * @param totalStaked Total staked amount
     * @param totalShares Total shares
     * @return Number of shares
     */
    function _calculateShares(
        uint256 amount,
        uint256 totalStaked,
        uint256 totalShares
    ) internal pure returns (uint256) {
        if (totalShares == 0 || totalStaked == 0) {
            return amount;
        }
        
        return amount.mulDiv(
            totalShares,
            totalStaked,
            Math.Rounding.Floor
        );
    }
    
    /**
     * @notice Check if user has staked with a validator
     * @param position User position
     * @param validatorAddress Validator address
     * @return True if user has staked with validator
     */
    function _hasValidator(
        Position storage position,
        address validatorAddress
    ) internal view returns (bool) {
        for (uint256 i = 0; i < position.validators.length; i++) {
            if (position.validators[i] == validatorAddress) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @notice Remove a validator from user's list
     * @param position User position
     * @param validatorAddress Validator address
     */
    function _removeValidator(
        Position storage position,
        address validatorAddress
    ) internal {
        for (uint256 i = 0; i < position.validators.length; i++) {
            if (position.validators[i] == validatorAddress) {
                // Swap with last element, then pop
                position.validators[i] = position.validators[position.validators.length - 1];
                position.validators.pop();
                break;
            }
        }
    }
    
    // ============ Emergency Functions ============
    
    /**
     * @notice Execute recovery in case of emergency
     * @dev Only callable by admin, allows recovering tokens/ETH
     * @param target Target address to call
     * @param data Call data
     */
    function emergencyExecute(
        address target,
        bytes calldata data
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bytes memory) {
        require(target != address(0), "StakingCore: Zero address");
        
        (bool success, bytes memory result) = target.call(data);
        require(success, "StakingCore: Execution failed");
        
        return result;
    }
    
    /**
     * @notice Receive function to accept native tokens
     */
    receive() external payable {
        // Funds received are distributed to the first active validator's reward pool
        if (msg.value > 0) {
            address validator = address(0);
            for (uint256 i = 0; i < validatorsList.length; i++) {
                if (validators[validatorsList[i]].isActive) {
                    validator = validatorsList[i];
                    break;
                }
            }
            
            if (validator != address(0)) {
                validators[validator].rewardPool += msg.value;
                validators[validator].lastUpdateTime = block.timestamp;
                emit ValidatorRewardsUpdated(validator, msg.value);
            }
        }
    }
} 