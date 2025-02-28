// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStakingManager} from "./interfaces/IStakingManager.sol";
import {AbstractStakingFlow} from "./abstract/AbstractStakingFlow.sol";
import {AggregatedStaking} from "./flows/AggregatedStaking.sol";
import {IndividualStaking} from "./flows/IndividualStaking.sol";
import {IUnifiedOracle} from "./interfaces/IUnifiedOracle.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title StakingManager
 * @notice Central management contract for both staking flows
 * @dev Acts as a gateway for users and controls flow-specific implementations
 */
contract StakingManager is IStakingManager, AccessControlEnumerable, ReentrancyGuard, Pausable {
    using Math for uint256;

    // ============ Constants ============
    uint256 private constant PRECISION = 1e18;
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MAX_COMMISSION = 3000; // 30% in basis points
    uint256 private constant MIN_STAKE_DEFAULT = 50 ether;
    
    // ============ Roles ============
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    // ============ State Variables ============
    
    // Flow implementations
    AggregatedStaking public aggregatedStaking;
    IndividualStaking public individualStaking;
    
    // Default flow setting
    StakingFlow public defaultFlow;
    
    // User registry
    mapping(address => UserRegistry) private _userRegistry;
    uint256 public totalUsers;
    uint256 public aggregatedUsers;
    uint256 public individualUsers;
    
    // Validator registry
    mapping(address => ValidatorInfo) public validators;
    address[] public validatorsList;
    
    // Configuration
    uint256 public minimumStake;
    IUnifiedOracle public oracle;
    
    struct UserRegistry {
        bool isRegistered;
        StakingFlow currentFlow;
    }
    
    // ============ Constructor ============
    constructor(
        address _oracle,
        address _operator,
        address _emergency
    ) {
        require(_oracle != address(0), "StakingManager: Zero oracle address");
        oracle = IUnifiedOracle(_oracle);
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, _operator);
        _grantRole(EMERGENCY_ROLE, _emergency);
        
        // Set default configuration
        minimumStake = MIN_STAKE_DEFAULT;
        defaultFlow = StakingFlow.AGGREGATED;
        
        // Deploy flow implementations
        aggregatedStaking = new AggregatedStaking(address(this));
        individualStaking = new IndividualStaking(address(this));
    }
    
    // ============ Admin Functions ============
    
    /// @inheritdoc IStakingManager
    function setDefaultFlow(StakingFlow newFlow) external onlyRole(OPERATOR_ROLE) {
        require(newFlow != defaultFlow, "StakingManager: Same flow");
        defaultFlow = newFlow;
        emit SystemFlowUpdated(newFlow);
    }
    
    /// @inheritdoc IStakingManager
    function setMinimumStake(uint256 newMinimumStake) external onlyRole(OPERATOR_ROLE) {
        require(newMinimumStake > 0, "StakingManager: Zero minimum");
        minimumStake = newMinimumStake;
        emit MinimumStakeUpdated(newMinimumStake);
    }
    
    /// @inheritdoc IStakingManager
    function registerValidator(
        address validatorAddress,
        string calldata cosmosAddress,
        string calldata name,
        uint256 commission
    ) external onlyRole(OPERATOR_ROLE) {
        require(validatorAddress != address(0), "StakingManager: Zero address");
        require(bytes(cosmosAddress).length > 0, "StakingManager: Empty cosmos address");
        require(bytes(name).length > 0, "StakingManager: Empty name");
        require(commission <= MAX_COMMISSION, "StakingManager: Commission too high");
        
        ValidatorInfo storage validator = validators[validatorAddress];
        require(!validator.isActive, "StakingManager: Already registered");
        
        // Register in the manager
        validator.evmAddress = validatorAddress;
        validator.cosmosAddress = cosmosAddress;
        validator.name = name;
        validator.commission = commission;
        validator.isActive = true;
        
        validatorsList.push(validatorAddress);
        
        // Register in the individual staking implementation
        individualStaking.registerValidator(validatorAddress);
        
        // Grant validator role
        _grantRole(VALIDATOR_ROLE, validatorAddress);
        
        emit ValidatorRegistered(validatorAddress, cosmosAddress, name);
    }
    
    /// @inheritdoc IStakingManager
    function updateValidator(
        address validatorAddress,
        string calldata cosmosAddress,
        string calldata name
    ) external onlyRole(OPERATOR_ROLE) {
        require(validatorAddress != address(0), "StakingManager: Zero address");
        
        ValidatorInfo storage validator = validators[validatorAddress];
        require(validator.isActive, "StakingManager: Not registered");
        
        validator.cosmosAddress = cosmosAddress;
        validator.name = name;
        
        emit ValidatorUpdated(validatorAddress, cosmosAddress, name);
    }
    
    /// @inheritdoc IStakingManager
    function setValidatorStatus(
        address validatorAddress,
        bool isActive
    ) external onlyRole(OPERATOR_ROLE) {
        ValidatorInfo storage validator = validators[validatorAddress];
        require(validator.evmAddress != address(0), "StakingManager: Not registered");
        
        // If deactivating, check that validator has no stakes in the individual flow
        if (!isActive && validator.isActive) {
            (uint256 validatorTotalShares, uint256 validatorTotalStaked, , , ) = 
                individualStaking.getValidatorInfo(validatorAddress);
                
            require(validatorTotalStaked == 0, "StakingManager: Validator has stakes");
            
            emit ValidatorDeactivated(validatorAddress);
        }
        // If activating
        else if (isActive && !validator.isActive) {
            emit ValidatorActivated(validatorAddress);
        }
        
        validator.isActive = isActive;
    }
    
    /// @inheritdoc IStakingManager
    function setValidatorCommission(
        address validatorAddress,
        uint256 commission
    ) external onlyRole(OPERATOR_ROLE) {
        require(commission <= MAX_COMMISSION, "StakingManager: Commission too high");
        
        ValidatorInfo storage validator = validators[validatorAddress];
        require(validator.isActive, "StakingManager: Not registered");
        
        validator.commission = commission;
        
        emit ValidatorCommissionUpdated(validatorAddress, commission);
    }
    
    // ============ Operator Functions ============
    
    /// @inheritdoc IStakingManager
    function compoundAggregatedRewards(
        uint256 rewardAmount
    ) external payable onlyRole(OPERATOR_ROLE) {
        require(msg.value == rewardAmount, "StakingManager: Incorrect value");
        
        // Delegate to the aggregated staking implementation
        aggregatedStaking.addRewards{value: rewardAmount}(rewardAmount, address(0));
        
        emit AggregatedRewardsCompounded(rewardAmount, aggregatedStaking.getCurrentSharePrice());
    }
    
    /// @inheritdoc IStakingManager
    function updateValidatorRewards(
        address validatorAddress,
        uint256 rewardAmount
    ) external payable onlyRole(OPERATOR_ROLE) {
        require(validatorAddress != address(0), "StakingManager: Zero address");
        require(msg.value == rewardAmount, "StakingManager: Incorrect value");
        
        ValidatorInfo storage validator = validators[validatorAddress];
        require(validator.isActive, "StakingManager: Not registered");
        
        // Delegate to the individual staking implementation
        individualStaking.addRewards{value: rewardAmount}(rewardAmount, validatorAddress);
        
        emit IndividualRewardsUpdated(validatorAddress, rewardAmount);
    }
    
    /// @inheritdoc IStakingManager
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }
    
    /// @inheritdoc IStakingManager
    function unpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }
    
    // ============ User Functions ============
    
    /// @inheritdoc IStakingManager
    function stake(
        address validatorAddress
    ) external payable nonReentrant whenNotPaused {
        require(msg.value >= minimumStake, "StakingManager: Below minimum");
        
        // For new users, assign default flow
        UserRegistry storage userRegistry = _userRegistry[msg.sender];
        if (!userRegistry.isRegistered) {
            userRegistry.isRegistered = true;
            userRegistry.currentFlow = defaultFlow;
            totalUsers++;
            
            if (defaultFlow == StakingFlow.AGGREGATED) {
                aggregatedUsers++;
            } else {
                individualUsers++;
            }
        }
        
        StakingFlow userFlow = userRegistry.currentFlow;
        uint256 shares;
        
        // Delegate to the appropriate flow implementation
        if (userFlow == StakingFlow.AGGREGATED) {
            // In aggregated flow, validator is ignored (use zero address)
            shares = aggregatedStaking.stake(msg.sender, msg.value, address(0));
            emit AggregatedStake(msg.sender, msg.value, shares);
        } else {
            // For individual flow, ensure valid validator
            address targetValidator = validatorAddress;
            
            // If no validator specified, choose first active one
            if (targetValidator == address(0)) {
                for (uint256 i = 0; i < validatorsList.length; i++) {
                    if (validators[validatorsList[i]].isActive) {
                        targetValidator = validatorsList[i];
                        break;
                    }
                }
                require(targetValidator != address(0), "StakingManager: No active validators");
            } else {
                // Verify provided validator
                require(validators[targetValidator].isActive, "StakingManager: Invalid validator");
            }
            
            shares = individualStaking.stake(msg.sender, msg.value, targetValidator);
            emit IndividualStake(msg.sender, targetValidator, msg.value, shares);
        }
    }
    
    /// @inheritdoc IStakingManager
    function unstake(
        uint256 amount,
        address validatorAddress
    ) external nonReentrant {
        UserRegistry storage userRegistry = _userRegistry[msg.sender];
        require(userRegistry.isRegistered, "StakingManager: Not registered");
        
        StakingFlow userFlow = userRegistry.currentFlow;
        uint256 shares;
        uint256 rewards;
        
        // Delegate to the appropriate flow implementation
        if (userFlow == StakingFlow.AGGREGATED) {
            // In aggregated flow, validator is ignored
            (shares, rewards) = aggregatedStaking.unstake(msg.sender, amount, address(0));
            
            // Transfer tokens back to user
            (bool success, ) = msg.sender.call{value: amount + rewards}("");
            require(success, "StakingManager: Transfer failed");
            
            emit AggregatedUnstake(msg.sender, amount, shares, rewards);
        } else {
            // For individual flow, ensure valid validator
            address targetValidator = validatorAddress;
            
            // If no validator specified, unstake proportionally from all validators
            if (targetValidator == address(0)) {
                (address[] memory userValidators, uint256[] memory allocations) = getUserValidators(msg.sender);
                require(userValidators.length > 0, "StakingManager: No stakes");
                
                uint256 totalUnstaked = 0;
                uint256 totalRewards = 0;
                
                for (uint256 i = 0; i < userValidators.length; i++) {
                    uint256 validatorAmount = amount * allocations[i] / 100;
                    
                    if (validatorAmount > 0 && totalUnstaked + validatorAmount <= amount) {
                        (uint256 validatorShares, uint256 validatorRewards) = 
                            individualStaking.unstake(msg.sender, validatorAmount, userValidators[i]);
                            
                        shares += validatorShares;
                        totalRewards += validatorRewards;
                        totalUnstaked += validatorAmount;
                        
                        emit IndividualUnstake(
                            msg.sender, 
                            userValidators[i], 
                            validatorAmount, 
                            validatorShares, 
                            validatorRewards
                        );
                    }
                }
                
                // If there's a remainder due to rounding, unstake from the first validator
                if (totalUnstaked < amount && userValidators.length > 0) {
                    uint256 remainder = amount - totalUnstaked;
                    (uint256 validatorShares, uint256 validatorRewards) = 
                        individualStaking.unstake(msg.sender, remainder, userValidators[0]);
                        
                    shares += validatorShares;
                    totalRewards += validatorRewards;
                    
                    emit IndividualUnstake(
                        msg.sender, 
                        userValidators[0], 
                        remainder, 
                        validatorShares, 
                        validatorRewards
                    );
                }
                
                // Transfer tokens back to user
                (bool success, ) = msg.sender.call{value: amount + totalRewards}("");
                require(success, "StakingManager: Transfer failed");
                
                rewards = totalRewards;
            } else {
                // Verify provided validator
                require(validators[targetValidator].isActive, "StakingManager: Invalid validator");
                
                (shares, rewards) = individualStaking.unstake(msg.sender, amount, targetValidator);
                
                // Transfer tokens back to user
                (bool success, ) = msg.sender.call{value: amount + rewards}("");
                require(success, "StakingManager: Transfer failed");
                
                emit IndividualUnstake(msg.sender, targetValidator, amount, shares, rewards);
            }
        }
        
        // Check if user has completely unstaked
        (uint256 remainingStake, , , ) = getUserStaking(msg.sender);
        if (remainingStake == 0) {
            // Update user counts
            if (userFlow == StakingFlow.AGGREGATED) {
                aggregatedUsers--;
            } else {
                individualUsers--;
            }
            
            totalUsers--;
            delete _userRegistry[msg.sender];
        }
    }
    
    /// @inheritdoc IStakingManager
    function claimRewards(
        address validatorAddress
    ) external nonReentrant returns (uint256) {
        UserRegistry storage userRegistry = _userRegistry[msg.sender];
        require(userRegistry.isRegistered, "StakingManager: Not registered");
        
        StakingFlow userFlow = userRegistry.currentFlow;
        uint256 rewards;
        
        // Delegate to the appropriate flow implementation
        if (userFlow == StakingFlow.AGGREGATED) {
            // In aggregated flow, validator is ignored
            rewards = aggregatedStaking.claimRewards(msg.sender, address(0));
            
            // Transfer rewards to user
            (bool success, ) = msg.sender.call{value: rewards}("");
            require(success, "StakingManager: Transfer failed");
            
            emit AggregatedRewardsClaimed(msg.sender, rewards);
        } else {
            // For individual flow, claim from specific validator or all
            rewards = individualStaking.claimRewards(msg.sender, validatorAddress);
            
            // Transfer rewards to user
            (bool success, ) = msg.sender.call{value: rewards}("");
            require(success, "StakingManager: Transfer failed");
            
            if (validatorAddress != address(0)) {
                emit IndividualRewardsClaimed(msg.sender, validatorAddress, rewards);
            } else {
                emit AggregatedRewardsClaimed(msg.sender, rewards);
            }
        }
        
        return rewards;
    }
    
    /// @inheritdoc IStakingManager
    function claimAndReinvest(
        address validatorAddress
    ) external nonReentrant whenNotPaused returns (uint256) {
        UserRegistry storage userRegistry = _userRegistry[msg.sender];
        require(userRegistry.isRegistered, "StakingManager: Not registered");
        
        StakingFlow userFlow = userRegistry.currentFlow;
        uint256 rewards;
        
        // First claim rewards
        if (userFlow == StakingFlow.AGGREGATED) {
            rewards = aggregatedStaking.claimRewards(msg.sender, address(0));
        } else {
            rewards = individualStaking.claimRewards(msg.sender, validatorAddress);
        }
        
        require(rewards > 0, "StakingManager: No rewards");
        
        uint256 shares;
        
        // Then reinvest
        if (userFlow == StakingFlow.AGGREGATED) {
            shares = aggregatedStaking.stake(msg.sender, rewards, address(0));
            emit AggregatedStake(msg.sender, rewards, shares);
        } else {
            // For individual flow, ensure valid validator
            address targetValidator = validatorAddress;
            
            // If no validator specified, reinvest proportionally across all validators
            if (targetValidator == address(0)) {
                (address[] memory userValidators, uint256[] memory allocations) = getUserValidators(msg.sender);
                require(userValidators.length > 0, "StakingManager: No stakes");
                
                uint256 totalReinvested = 0;
                
                for (uint256 i = 0; i < userValidators.length; i++) {
                    uint256 validatorAmount = rewards * allocations[i] / 100;
                    
                    if (validatorAmount > 0 && totalReinvested + validatorAmount <= rewards) {
                        uint256 validatorShares = 
                            individualStaking.stake(msg.sender, validatorAmount, userValidators[i]);
                            
                        shares += validatorShares;
                        totalReinvested += validatorAmount;
                        
                        emit IndividualStake(msg.sender, userValidators[i], validatorAmount, validatorShares);
                    }
                }
                
                // If there's a remainder due to rounding, stake with the first validator
                if (totalReinvested < rewards && userValidators.length > 0) {
                    uint256 remainder = rewards - totalReinvested;
                    uint256 validatorShares = 
                        individualStaking.stake(msg.sender, remainder, userValidators[0]);
                        
                    shares += validatorShares;
                    
                    emit IndividualStake(msg.sender, userValidators[0], remainder, validatorShares);
                }
            } else {
                // Verify provided validator
                require(validators[targetValidator].isActive, "StakingManager: Invalid validator");
                
                shares = individualStaking.stake(msg.sender, rewards, targetValidator);
                emit IndividualStake(msg.sender, targetValidator, rewards, shares);
            }
        }
        
        emit UserReinvested(msg.sender, rewards, shares);
        return rewards;
    }
    
    /// @inheritdoc IStakingManager
    function changeUserFlow(StakingFlow newFlow) external nonReentrant {
        UserRegistry storage userRegistry = _userRegistry[msg.sender];
        require(userRegistry.isRegistered, "StakingManager: Not registered");
        require(userRegistry.currentFlow != newFlow, "StakingManager: Already in flow");
        
        StakingFlow oldFlow = userRegistry.currentFlow;
        bytes memory userData;
        
        // Migrate from old flow to new flow
        if (oldFlow == StakingFlow.AGGREGATED) {
            // Migrate from aggregated to individual
            userData = aggregatedStaking.migrateUser(msg.sender, "");
            
            // Parse aggregated flow data
            (uint256 shares, uint256 stakedAmount, uint256 rewards) = 
                abi.decode(userData, (uint256, uint256, uint256));
            
            // Choose a default validator (first active one)
            address defaultValidator = address(0);
            for (uint256 i = 0; i < validatorsList.length; i++) {
                if (validators[validatorsList[i]].isActive) {
                    defaultValidator = validatorsList[i];
                    break;
                }
            }
            require(defaultValidator != address(0), "StakingManager: No active validators");
            
            // Stake in individual flow
            if (stakedAmount > 0) {
                individualStaking.stake(msg.sender, stakedAmount, defaultValidator);
                emit IndividualStake(msg.sender, defaultValidator, stakedAmount, shares);
            }
            
            // Transfer rewards if any
            if (rewards > 0) {
                (bool success, ) = msg.sender.call{value: rewards}("");
                require(success, "StakingManager: Transfer failed");
                emit AggregatedRewardsClaimed(msg.sender, rewards);
            }
            
            // Update counters
            aggregatedUsers--;
            individualUsers++;
        } else {
            // Migrate from individual to aggregated
            userData = individualStaking.migrateUser(msg.sender, "");
            
            // Parse individual flow data
            (uint256 totalShares, uint256 totalStaked, address[] memory userValidators, uint256 rewards) = 
                abi.decode(userData, (uint256, uint256, address[], uint256));
            
            // Stake in aggregated flow
            if (totalStaked > 0) {
                aggregatedStaking.stake(msg.sender, totalStaked, address(0));
                emit AggregatedStake(msg.sender, totalStaked, totalShares);
            }
            
            // Transfer rewards if any
            if (rewards > 0) {
                (bool success, ) = msg.sender.call{value: rewards}("");
                require(success, "StakingManager: Transfer failed");
                emit AggregatedRewardsClaimed(msg.sender, rewards);
            }
            
            // Update counters
            individualUsers--;
            aggregatedUsers++;
        }
        
        // Update user's flow
        userRegistry.currentFlow = newFlow;
        
        emit UserFlowChanged(msg.sender, oldFlow, newFlow);
    }
    
    // ============ View Functions ============
    
    /// @inheritdoc IStakingManager
    function getValidatorInfo(
        address validatorAddress
    ) external view returns (ValidatorInfo memory) {
        return validators[validatorAddress];
    }
    
    /// @inheritdoc IStakingManager
    function getUserStaking(
        address user
    ) public view returns (
        uint256 stakedAmount,
        uint256 sharesAmount,
        uint256 pendingRewards,
        StakingFlow flowType
    ) {
        UserRegistry storage userRegistry = _userRegistry[user];
        if (!userRegistry.isRegistered) {
            return (0, 0, 0, defaultFlow);
        }
        
        StakingFlow userFlow = userRegistry.currentFlow;
        
        if (userFlow == StakingFlow.AGGREGATED) {
            (uint256 shares, uint256 staked, uint256 lastClaim, bool isActive) = 
                aggregatedStaking.getUserInfo(user);
            
            if (!isActive) {
                return (0, 0, 0, userFlow);
            }
            
            uint256 rewards = aggregatedStaking.calculateRewards(user, address(0));
            
            return (staked, shares, rewards, userFlow);
        } else {
            (uint256 totalShares, uint256 totalStaked, uint256 lastClaim, address[] memory validators) = 
                individualStaking.getUserInfo(user);
            
            if (validators.length == 0) {
                return (0, 0, 0, userFlow);
            }
            
            uint256 rewards = individualStaking.calculateRewards(user, address(0));
            
            return (totalStaked, totalShares, rewards, userFlow);
        }
    }
    
    /// @inheritdoc IStakingManager
    function getUserValidators(
        address user
    ) public view returns (
        address[] memory validators,
        uint256[] memory allocations
    ) {
        UserRegistry storage userRegistry = _userRegistry[user];
        if (!userRegistry.isRegistered) {
            return (new address[](0), new uint256[](0));
        }
        
        StakingFlow userFlow = userRegistry.currentFlow;
        
        if (userFlow == StakingFlow.AGGREGATED) {
            // For aggregated flow, return an array with just a zero address
            validators = new address[](1);
            allocations = new uint256[](1);
            validators[0] = address(0);
            allocations[0] = 100; // 100% allocation
        } else {
            (uint256 totalShares, uint256 totalStaked, uint256 lastClaim, address[] memory userValidators) = 
                individualStaking.getUserInfo(user);
            
            validators = userValidators;
            allocations = new uint256[](validators.length);
            
            if (totalStaked == 0) {
                return (validators, allocations);
            }
            
            // Calculate allocation percentages
            for (uint256 i = 0; i < validators.length; i++) {
                (uint256 shares, uint256 staked, , bool isActive) = 
                    individualStaking.getUserValidatorStake(user, validators[i]);
                
                if (isActive && staked > 0) {
                    allocations[i] = (staked * 100) / totalStaked;
                } else {
                    allocations[i] = 0;
                }
            }
        }
        
        return (validators, allocations);
    }
    
    /// @inheritdoc IStakingManager
    function getSystemStats() external view returns (
        uint256 _totalStaked,
        uint256 _totalUsers,
        uint256 _aggregatedUsers,
        uint256 _individualUsers,
        uint256 _activeValidators
    ) {
        uint256 aggregatedStaked = aggregatedStaking.getTotalStaked();
        uint256 individualStaked = individualStaking.getTotalStaked();
        
        uint256 activeValidatorsCount = 0;
        for (uint256 i = 0; i < validatorsList.length; i++) {
            if (validators[validatorsList[i]].isActive) {
                activeValidatorsCount++;
            }
        }
        
        return (
            aggregatedStaked + individualStaked,
            totalUsers,
            aggregatedUsers,
            individualUsers,
            activeValidatorsCount
        );
    }
    
    /// @inheritdoc IStakingManager
    function getDefaultFlow() external view returns (StakingFlow) {
        return defaultFlow;
    }
    
    /// @inheritdoc IStakingManager
    function getCurrentAPR() external view returns (uint256) {
        // Get current APR from oracle (in basis points)
        try oracle.getCurrentRewards() returns (uint256 amount, uint256 timestamp) {
            // Return a fixed APR for now - in production this would be calculated based on rewards
            return 1000; // 10% in basis points
        } catch {
            return 0;
        }
    }
    
    /// @inheritdoc IStakingManager
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
    
    // ============ Emergency Functions ============
    
    /**
     * @notice Execute recovery in case of emergency
     * @dev Only callable by admin, allows recovering tokens/ETH from implementations
     * @param target Target contract to call
     * @param data Call data
     */
    function emergencyExecute(
        address target,
        bytes calldata data
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bytes memory) {
        require(target != address(0), "StakingManager: Zero address");
        
        (bool success, bytes memory result) = target.call(data);
        require(success, "StakingManager: Execution failed");
        
        return result;
    }
    
    /**
     * @notice Receive function to accept native tokens
     */
    receive() external payable {
        // Native tokens received are added to aggregated rewards by default
        if (msg.value > 0) {
            aggregatedStaking.addRewards{value: msg.value}(msg.value, address(0));
            emit AggregatedRewardsCompounded(msg.value, aggregatedStaking.getCurrentSharePrice());
        }
    }
} 