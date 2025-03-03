// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStakingCore} from "./interfaces/IStakingCore.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StakingProxy
 * @notice User-facing contract that acts as the main entry point to the staking system
 * @dev Proxies user calls to the StakingCore contract with additional features
 */
contract StakingProxy is Ownable {
    // ============ State Variables ============
    
    // Core contracts
    address public stakingCore;
    address public oracle;
    
    // Settings
    bool public paused;
    
    // ============ Events ============
    
    event CoreContractUpdated(address indexed newCoreContract);
    event OracleUpdated(address indexed newOracle);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event Staked(address indexed user, address indexed validator, uint256 amount);
    event Unstaked(address indexed user, address indexed validator, uint256 amount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 amount);
    
    // ============ Constructor ============
    
    constructor(address _stakingCore, address _oracle) Ownable(msg.sender) {
        require(_stakingCore != address(0), "StakingProxy: Zero core address");
        require(_oracle != address(0), "StakingProxy: Zero oracle address");
        stakingCore = _stakingCore;
        oracle = _oracle;
    }
    
    // ============ Modifiers ============
    
    modifier whenNotPaused() {
        require(!paused, "StakingProxy: Paused");
        _;
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Update the StakingCore contract address
     * @param _stakingCore New StakingCore address
     */
    function setStakingCore(address _stakingCore) external onlyOwner {
        require(_stakingCore != address(0), "StakingProxy: Zero core address");
        stakingCore = _stakingCore;
        emit CoreContractUpdated(_stakingCore);
    }
    
    /**
     * @notice Update the Oracle contract address
     * @param _oracle New Oracle address
     */
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "StakingProxy: Zero oracle address");
        oracle = _oracle;
        emit OracleUpdated(_oracle);
    }
    
    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }
    
    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }
    
    // ============ User Functions ============
    
    /**
     * @notice Stake tokens with a validator
     * @param validatorAddress Validator to stake with
     */
    function stake(address validatorAddress) external payable whenNotPaused {
        IStakingCore core = IStakingCore(stakingCore);
        
        // Forward call to core contract
        core.stake{value: msg.value}(validatorAddress);
        
        emit Staked(msg.sender, validatorAddress, msg.value);
    }
    
    /**
     * @notice Unstake tokens from a validator
     * @param amount Amount to unstake
     * @param validatorAddress Validator to unstake from
     */
    function unstake(uint256 amount, address validatorAddress) external whenNotPaused {
        IStakingCore core = IStakingCore(stakingCore);
        
        // Get pre-call balance
        uint256 preBalance = address(this).balance;
        
        // Forward call to core contract
        core.unstake(amount, validatorAddress);
        
        // Calculate rewards (difference between post and pre balance)
        uint256 totalReceived = address(this).balance - preBalance;
        uint256 rewards = totalReceived - amount;
        
        // Transfer funds to user
        (bool success, ) = msg.sender.call{value: totalReceived}("");
        require(success, "StakingProxy: Transfer failed");
        
        emit Unstaked(msg.sender, validatorAddress, amount, rewards);
    }
    
    /**
     * @notice Claim rewards from all validators
     */
    function claimRewards() external whenNotPaused {
        IStakingCore core = IStakingCore(stakingCore);
        
        // Get pre-call balance
        uint256 preBalance = address(this).balance;
        
        // Claim from all validators (pass address(0))
        core.claimRewards(address(0));
        
        // Calculate rewards (difference between post and pre balance)
        uint256 rewards = address(this).balance - preBalance;
        
        // Transfer funds to user
        (bool success, ) = msg.sender.call{value: rewards}("");
        require(success, "StakingProxy: Transfer failed");
        
        emit RewardsClaimed(msg.sender, rewards);
    }
    
    /**
     * @notice Reinvest rewards with a specified validator
     * @param validatorAddress Validator to reinvest with
     * @return Amount reinvested
     */
    function reinvestRewards(address validatorAddress) external whenNotPaused returns (uint256) {
        IStakingCore core = IStakingCore(stakingCore);
        
        // Forward call to core contract
        uint256 reinvested = core.claimAndReinvest(validatorAddress);
        
        return reinvested;
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get user's staking position
     * @param user User address
     * @return totalStaked Total staked by user
     * @return pendingRewards Pending rewards
     * @return validatorCount Number of validators user is staked with
     */
    function getUserPosition(address user) external view returns (
        uint256 totalStaked,
        uint256 pendingRewards,
        uint256 validatorCount
    ) {
        IStakingCore core = IStakingCore(stakingCore);
        
        (totalStaked, , pendingRewards, validatorCount) = core.getUserPosition(user);
        
        return (totalStaked, pendingRewards, validatorCount);
    }
    
    /**
     * @notice Get user's validators
     * @param user User address
     * @return validators Array of validator addresses
     * @return stakedAmounts Array of staked amounts
     * @return rewards Array of pending rewards
     */
    function getUserValidators(address user) external view returns (
        address[] memory validators,
        uint256[] memory stakedAmounts,
        uint256[] memory rewards
    ) {
        IStakingCore core = IStakingCore(stakingCore);
        
        uint256[] memory shares;
        (validators, stakedAmounts, shares, rewards) = core.getUserValidators(user);
        
        return (validators, stakedAmounts, rewards);
    }
    
    /**
     * @notice Get active validators
     * @return Array of active validator addresses
     */
    function getActiveValidators() external view returns (address[] memory) {
        IStakingCore core = IStakingCore(stakingCore);
        return core.getActiveValidators();
    }
    
    /**
     * @notice Get validator information
     * @param validatorAddress Validator address
     * @return evmAddress EVM address of validator
     * @return cosmosAddress Cosmos address of validator
     * @return name Validator name
     * @return commission Commission rate in basis points
     * @return totalStaked Total amount staked with validator
     * @return isActive Whether validator is active
     */
    function getValidatorInfo(address validatorAddress) external view returns (
        address evmAddress,
        string memory cosmosAddress,
        string memory name,
        uint256 commission,
        uint256 totalStaked,
        bool isActive
    ) {
        IStakingCore core = IStakingCore(stakingCore);
        
        uint256 totalShares;
        uint256 rewardPool;
        uint256 lastUpdateTime;
        
        (
            evmAddress,
            cosmosAddress,
            name,
            commission,
            totalStaked,
            totalShares,
            rewardPool,
            lastUpdateTime,
            isActive
        ) = core.getValidatorInfo(validatorAddress);
        
        return (
            evmAddress,
            cosmosAddress,
            name,
            commission,
            totalStaked,
            isActive
        );
    }
    
    /**
     * @notice Get current APR
     * @return Current APR in basis points
     */
    function getCurrentAPR() external view returns (uint256) {
        IStakingCore core = IStakingCore(stakingCore);
        return core.getCurrentAPR();
    }
    
    /**
     * @notice Get XFI price
     * @return price Current price
     * @return timestamp Time of last price update
     */
    function getXFIPrice() external view returns (uint256 price, uint256 timestamp) {
        IOracle oracleContract = IOracle(oracle);
        return oracleContract.getXFIPrice();
    }
    
    /**
     * @notice Receive function to accept native tokens
     */
    receive() external payable {
        // Simply holds funds until they are processed
    }
} 