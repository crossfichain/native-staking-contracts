// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IDIAOracle} from "./interfaces/IDIAOracle.sol";
import {INativeStaking} from "./interfaces/INativeStaking.sol";
import {IStakingOperator} from "./interfaces/IStakingOperator.sol";

/**
 * @title NativeStaking
 * @notice Implementation of native token staking with delegated token shares
 * @dev Inspired by ERC4626 vault standard for share calculation and distribution
 */
contract NativeStaking is
    INativeStaking,
    IStakingOperator,
    Ownable,
    ReentrancyGuard,
    AccessControl,
    Pausable
{
    using Math for uint256;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Constants
    uint256 private constant DELEGATED_TOKEN_PRICE = 0.04 ether;
    uint256 private constant MIN_STAKE = 50 ether;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant COMPOUND_PERIOD = 2 weeks;
    uint256 private constant SLASH_PENALTY_RATE = 500; // 5% = 500 basis points

    // State variables
    IDIAOracle public immutable oracle;

    uint256 public totalStaked;
    uint256 public totalShares;
    uint256 public lastCompoundTimestamp;
    uint256 public rewardPool;
    bool public slashingActive;

    mapping(address => StakingPosition) private _positions;

    constructor(
        address _oracle,
        address _operator,
        address _emergency
    ) Ownable(msg.sender) Pausable() ReentrancyGuard() {
        oracle = IDIAOracle(_oracle);
        lastCompoundTimestamp = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, _operator);
        _grantRole(EMERGENCY_ROLE, _emergency);
    }

    /**
     * @notice Stakes native tokens and mints shares
     * @dev Implements share calculation similar to ERC4626
     */
    function stake() external payable override nonReentrant whenNotPaused {
        require(msg.value >= MIN_STAKE, "NativeStaking: Below minimum stake");

        uint256 shares = _convertToShares(msg.value, Math.Rounding.Floor);
        require(shares > 0, "NativeStaking: Zero shares");

        uint256 delegatedAmount = _calculateDelegatedAmount(msg.value);

        _positions[msg.sender].lockedAmount += msg.value;
        _positions[msg.sender].collateralAmount += delegatedAmount;
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
        require(
            position.lockedAmount >= amount,
            "NativeStaking: Insufficient stake"
        );

        uint256 shares = _convertToShares(amount, Math.Rounding.Ceil);
        require(shares > 0, "NativeStaking: Zero shares");

        uint256 rewards = _calculateRewards(msg.sender);

        position.lockedAmount -= amount;
        position.collateralAmount -= _calculateDelegatedAmount(amount);
        position.shares -= shares;

        totalStaked -= amount;
        totalShares -= shares;

        (bool success, ) = msg.sender.call{value: amount + rewards}("");
        require(success, "NativeStaking: Transfer failed");

        emit Unstaked(msg.sender, amount, rewards);
    }

    /**
     * @notice Compounds rewards by converting to shares
     * @dev Only callable by authorized address
     */
    function compoundRewards() external override onlyRole(OPERATOR_ROLE) {
        uint256 currentRewards = rewardPool;
        require(currentRewards > 0, "NativeStaking: No rewards");

        uint256 newShares = _convertToShares(
            currentRewards,
            Math.Rounding.Floor
        );
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
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function previewUnstake(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /**
     * @notice Internal share conversion functions
     */
    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        uint256 supply = totalShares;
        return
            (supply == 0)
                ? assets
                : assets.mulDiv(supply, totalStaked, rounding);
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        uint256 supply = totalShares;
        return
            (supply == 0)
                ? shares
                : shares.mulDiv(totalStaked, supply, rounding);
    }

    /**
     * @notice Calculates delegated token amount based on native token price
     */
    function _calculateDelegatedAmount(
        uint256 amount
    ) internal view returns (uint256) {
        uint256 nativePrice = _getNativeTokenPrice();
        return
            amount.mulDiv(
                nativePrice,
                DELEGATED_TOKEN_PRICE,
                Math.Rounding.Floor
            );
    }

    /**
     * @notice Calculates pending rewards for an account
     */
    function _calculateRewards(
        address account
    ) internal view returns (uint256) {
        StakingPosition storage position = _positions[account];
        if (position.shares == 0) return 0;

        uint256 accountShare = position.shares.mulDiv(
            rewardPool,
            totalShares,
            Math.Rounding.Floor
        );
        return accountShare;
    }

    /**
     * @notice Gets native token price from oracle
     */
    function _getNativeTokenPrice() internal view returns (uint256) {
        (uint256 price, ) = oracle.getValue("XFI/USD");
        require(price > 0, "NativeStaking: Invalid price");
        return price;
    }

    /**
     * @notice View functions
     */
    function getStakingPosition(
        address user
    )
        external
        view
        override
        returns (
            uint256 lockedAmount,
            uint256 collateralAmount,
            uint256 shares,
            uint256 pendingRewards
        )
    {
        StakingPosition storage position = _positions[user];
        return (
            position.lockedAmount,
            position.collateralAmount,
            position.shares,
            _calculateRewards(user)
        );
    }

    function getCurrentConversionRate()
        external
        view
        override
        returns (uint256)
    {
        return
            _getNativeTokenPrice().mulDiv(
                PRECISION,
                DELEGATED_TOKEN_PRICE,
                Math.Rounding.Floor
            );
    }

    /**
     * @notice Receive function to accept native tokens
     */
    receive() external payable {
        rewardPool += msg.value;
        emit RewardsDistributed(msg.value, 0);
    }

    function distributeRewards(
        uint256 amount,
        uint256 newCollateralAmount
    ) external override onlyRole(OPERATOR_ROLE) nonReentrant {
        require(amount > 0, "NativeStaking: Zero rewards");
        require(
            block.timestamp >= lastCompoundTimestamp + COMPOUND_PERIOD,
            "NativeStaking: Too early"
        );

        rewardPool += amount;
        emit RewardsDistributed(amount, newCollateralAmount);
    }

    function handleSlashing(
        uint256 slashAmount,
        uint256 timestamp
    ) external override onlyRole(OPERATOR_ROLE) {
        require(!slashingActive, "NativeStaking: Slashing already active");

        slashingActive = true;
        uint256 penaltyAmount = (totalStaked * SLASH_PENALTY_RATE) / 10000;

        emit ValidatorSlashed(penaltyAmount, timestamp);
    }

    // Emergency functions
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }

    function handleSlashing(uint256 slashAmount) external override {}

    // function operator() external view returns (bool) {
    //     return hasRole(OPERATOR_ROLE, msg.sender);
    // }

}