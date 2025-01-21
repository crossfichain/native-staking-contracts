// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IDIAOracle} from "./interfaces/IDIAOracle.sol";
import {INativeStaking} from "./interfaces/INativeStaking.sol";

/**
 * @title NativeStaking
 * @notice Implementation of native token staking with delegated token shares
 * @dev Inspired by ERC4626 vault standard for share calculation and distribution
 */
contract NativeStaking is INativeStaking, Ownable, ReentrancyGuard {
    using Math for uint256;

    // Constants
    uint256 private constant DELEGATED_TOKEN_PRICE = 0.04 ether;
    uint256 private constant MIN_STAKE = 50 ether;
    uint256 private constant PRECISION = 1e18;

    // State variables
    IDIAOracle public immutable oracle;
    
    uint256 public totalStaked;
    uint256 public totalShares;
    uint256 public lastRewardTimestamp;
    uint256 public rewardPool;

    mapping(address => StakingPosition) private _positions;

    constructor(address _oracle) Ownable(msg.sender) {
        oracle = IDIAOracle(_oracle);
        lastRewardTimestamp = block.timestamp;
    }

    /**
     * @notice Stakes native tokens and mints shares
     * @dev Implements share calculation similar to ERC4626
     */
    function stake() external payable override nonReentrant {
        require(msg.value >= MIN_STAKE, "NativeStaking: Below minimum stake");
        
        uint256 shares = _convertToShares(msg.value, Math.Rounding.Floor);
        require(shares > 0, "NativeStaking: Zero shares");

        uint256 delegatedAmount = _calculateDelegatedAmount(msg.value);
        
        _positions[msg.sender].lockedAmount += msg.value;
        _positions[msg.sender].shares += shares;
        _positions[msg.sender].lastRewardTimestamp = block.timestamp;
        
        totalStaked += msg.value;
        totalShares += shares;
        
        emit Staked(msg.sender, msg.value, delegatedAmount);
    }

    /**
     * @notice Unstakes native tokens and burns shares
     * @param amount Amount of native tokens to unstake
     */
    function unstake(uint256 amount) external override nonReentrant {
        StakingPosition storage position = _positions[msg.sender];
        require(position.stakedAmount >= amount, "NativeStaking: Insufficient stake");

        uint256 shares = _convertToShares(amount, Math.Rounding.Up);
        require(shares > 0, "NativeStaking: Zero shares");

        uint256 rewards = _calculateRewards(msg.sender);
        
        position.lockedAmount -= amount;
        position.shares -= shares;
        totalStaked -= amount;
        totalShares -= shares;

        // Transfer native tokens and rewards
        (bool success, ) = msg.sender.call{value: amount + rewards}("");
        require(success, "NativeStaking: Transfer failed");

        emit Unstaked(msg.sender, amount, rewards);
    }

    /**
     * @notice Compounds rewards by converting to shares
     * @dev Only callable by authorized address
     */
    function compoundRewards() external override onlyOwner {
        uint256 currentRewards = rewardPool;
        require(currentRewards > 0, "NativeStaking: No rewards");

        uint256 newShares = _convertToShares(currentRewards, Math.Rounding.Down);
        uint256 delegatedAmount = _calculateDelegatedAmount(currentRewards);

        rewardPool = 0;
        totalShares += newShares;
        totalStaked += currentRewards;

        emit RewardsCompounded(currentRewards, delegatedAmount);
    }

    /**
     * @notice Preview functions inspired by ERC4626
     */
    function previewStake(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    function previewUnstake(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Up);
    }

    /**
     * @notice Internal share conversion functions
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalShares;
        return (supply == 0) 
            ? assets
            : assets.mulDiv(supply, totalStaked, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalShares;
        return (supply == 0)
            ? shares
            : shares.mulDiv(totalStaked, supply, rounding);
    }

    /**
     * @notice Calculates delegated token amount based on native token price
     */
    function _calculateDelegatedAmount(uint256 amount) internal view returns (uint256) {
        uint256 nativePrice = _getNativeTokenPrice();
        return amount.mulDiv(nativePrice, DELEGATED_TOKEN_PRICE, Math.Rounding.Down);
    }

    /**
     * @notice Calculates pending rewards for an account
     */
    function _calculateRewards(address account) internal view returns (uint256) {
        StakingPosition storage position = _positions[account];
        if (position.shares == 0) return 0;

        uint256 accountShare = position.shares.mulDiv(rewardPool, totalShares, Math.Rounding.Down);
        return accountShare;
    }

    /**
     * @notice Gets native token price from oracle
     */
    function _getNativeTokenPrice() internal view returns (uint256) {
        (uint256 price,) = oracle.getPrice("NATIVE");
        require(price > 0, "NativeStaking: Invalid price");
        return price;
    }

    /**
     * @notice View functions
     */
    function getStakingPosition(address user) external view override returns (
        uint256 stakedAmount,
        uint256 shares,
        uint256 pendingRewards
    ) {
        StakingPosition storage position = _positions[user];
        return (
            position.stakedAmount,
            position.shares,
            _calculateRewards(user)
        );
    }

    function getCurrentConversionRate() external view override returns (uint256) {
        return _getNativeTokenPrice().mulDiv(PRECISION, DELEGATED_TOKEN_PRICE, Math.Rounding.Down);
    }

    /**
     * @notice Receive function to accept native tokens
     */
    receive() external payable {
        rewardPool += msg.value;
        emit RewardsDistributed(msg.value, 0);
    }
}