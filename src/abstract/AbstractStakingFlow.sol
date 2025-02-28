// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStakingManager} from "../interfaces/IStakingManager.sol";

/**
 * @title AbstractStakingFlow
 * @notice Base contract for staking flow implementations
 * @dev Should be inherited by both AggregatedStaking and IndividualStaking
 */
abstract contract AbstractStakingFlow is ReentrancyGuard, Pausable {
    using Math for uint256;

    // ============ Constants and Immutables ============
    uint256 internal constant PRECISION = 1e18; // For fixed-point calculations
    uint256 internal constant BASIS_POINTS = 10000; // For percentage calculations
    uint256 internal constant MAX_COMMISSION = 3000; // 30% in basis points
    
    address public immutable manager; // Reference to the StakingManager contract
    
    // ============ State Variables ============
    uint256 internal _totalStaked;    // Total staked in this flow
    uint256 internal _totalShares;    // Total shares in this flow
    uint256 internal _usersCount;     // Number of users in this flow
    
    // ============ Constructor ============
    constructor(address _manager) {
        require(_manager != address(0), "AbstractStakingFlow: Zero manager address");
        manager = _manager;
    }
    
    // ============ Modifiers ============
    
    /// @notice Ensures caller is the manager contract
    modifier onlyManager() {
        require(msg.sender == manager, "AbstractStakingFlow: Not manager");
        _;
    }
    
    // ============ External Functions (to be implemented) ============
    
    /// @notice Stake tokens into the flow
    /// @param user Address of the user staking
    /// @param amount Amount of tokens to stake
    /// @param validator Target validator (may be ignored in aggregated flow)
    /// @return shares Number of shares minted
    function stake(
        address user, 
        uint256 amount, 
        address validator
    ) external virtual returns (uint256 shares);
    
    /// @notice Unstake tokens from the flow
    /// @param user Address of the user unstaking
    /// @param amount Amount of tokens to unstake
    /// @param validator Target validator (may be ignored in aggregated flow)
    /// @return shares Number of shares burned
    /// @return rewards Amount of rewards claimed
    function unstake(
        address user, 
        uint256 amount, 
        address validator
    ) external virtual returns (uint256 shares, uint256 rewards);
    
    /// @notice Claim rewards from the flow
    /// @param user Address of the user claiming
    /// @param validator Target validator (may be ignored in aggregated flow)
    /// @return Amount of rewards claimed
    function claimRewards(
        address user, 
        address validator
    ) external virtual returns (uint256);
    
    /// @notice Add rewards to the flow
    /// @param amount Amount of rewards to add
    /// @param validator Target validator (may be ignored in aggregated flow)
    function addRewards(
        uint256 amount, 
        address validator
    ) external virtual payable;
    
    /// @notice Migrate a user to a different flow
    /// @param user Address of the user to migrate
    /// @param stakingData Data to migrate (interpretation depends on flow)
    /// @return stakingData User's current staking data for the new flow
    function migrateUser(
        address user, 
        bytes calldata stakingData
    ) external virtual returns (bytes memory);
    
    // ============ View Functions ============
    
    /// @notice Calculate number of shares for a given amount
    /// @param amount Amount of tokens
    /// @return Number of shares
    function calculateShares(uint256 amount) public view virtual returns (uint256);
    
    /// @notice Calculate amount of tokens for a given number of shares
    /// @param shares Number of shares
    /// @return Amount of tokens
    function calculateAmount(uint256 shares) public view virtual returns (uint256);
    
    /// @notice Calculate pending rewards for a user
    /// @param user Address of the user
    /// @param validator Target validator (may be ignored in aggregated flow)
    /// @return Amount of pending rewards
    function calculateRewards(
        address user, 
        address validator
    ) public view virtual returns (uint256);
    
    /// @notice Get total staked in this flow
    /// @return Total staked amount
    function getTotalStaked() external view returns (uint256) {
        return _totalStaked;
    }
    
    /// @notice Get total shares in this flow
    /// @return Total shares
    function getTotalShares() external view returns (uint256) {
        return _totalShares;
    }
    
    /// @notice Get number of users in this flow
    /// @return Number of users
    function getUsersCount() external view returns (uint256) {
        return _usersCount;
    }
} 