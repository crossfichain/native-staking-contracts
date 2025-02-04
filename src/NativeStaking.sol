// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
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
    ReentrancyGuard,
    AccessControlEnumerable,
    Pausable,
    ERC20
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
    IPriceOracle public immutable oracle;

    uint256 public totalStaked;
    uint256 public totalShares;
    uint256 public lastCompoundTimestamp;
    uint256 public rewardPool;
    bool public slashingActive;

    mapping(address => StakingPosition) private _positions;

    // Add state variable for tracking stakers
    address[] public stakers;
    mapping(address => bool) public isStaker;

    constructor(
        address _oracle,
        address _operator,
        address _emergency
    ) ERC20("Staked Native Token", "stNATIVE") {
        oracle = IPriceOracle(_oracle);
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

        if (!isStaker[msg.sender]) {
            stakers.push(msg.sender);
            isStaker[msg.sender] = true;
        }

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
    function compoundRewards() external payable onlyRole(OPERATOR_ROLE) {
        uint256 currentRewards = msg.value;
        require(currentRewards > 0, "NativeStaking: No rewards");

        uint256 delegatedAmount = _calculateDelegatedAmount(currentRewards);
        totalStaked += currentRewards;

        // Iterate through stakers array
        for (uint256 i = 0; i < stakers.length; i++) {
            _compoundPositionRewards(stakers[i], currentRewards);
        }

        emit RewardsCompounded(currentRewards, delegatedAmount);
    }

    function _compoundPositionRewards(address user, uint256 totalRewards) internal {
        StakingPosition storage position = _positions[user];
        if (position.shares == 0) return;

        // Calculate user's share of rewards
        uint256 userRewards = position.shares.mulDiv(
            totalRewards,
            totalShares,
            Math.Rounding.Floor
        );

        // Update position's locked amount and collateral
        position.lockedAmount += userRewards;
        position.collateralAmount += _calculateDelegatedAmount(userRewards);
        position.lastRewardTimestamp = block.timestamp;
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
        uint256 supply = totalSupply();
        return
            (supply == 0)
                ? assets
                : assets.mulDiv(supply, totalAssets(), rounding);
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return
            (supply == 0)
                ? shares
                : shares.mulDiv(totalAssets(), supply, rounding);
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
        (uint256 price, ) = oracle.getXFIPrice();
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
        // rewardPool += msg.value;
        // emit RewardsDistributed(msg.value, 0);
    }

    // function distributeRewards(
    //     uint256 amount,
    //     uint256 newCollateralAmount
    // ) external override onlyRole(OPERATOR_ROLE) nonReentrant {
    //     require(amount > 0, "NativeStaking: Zero rewards");
    //     require(
    //         block.timestamp >= lastCompoundTimestamp + COMPOUND_PERIOD,
    //         "NativeStaking: Too early"
    //     );

    //     // Get rewards from oracle
    //     (uint256 oracleRewards, uint256 timestamp) = oracle.getCurrentRewards();
    //     require(oracleRewards == amount, "NativeStaking: Invalid reward amount");
    //     require(timestamp >= lastCompoundTimestamp, "NativeStaking: Stale reward data");

    //     rewardPool += amount;
    //     lastCompoundTimestamp = block.timestamp;
        
    //     emit RewardsDistributed(amount, newCollateralAmount);
    }

    // function handleSlashing(
    //     uint256 slashAmount,
    //     uint256 timestamp
    // ) external override onlyRole(OPERATOR_ROLE) {
    //     require(!slashingActive, "NativeStaking: Slashing already active");

    //     slashingActive = true;
    //     uint256 penaltyAmount = (totalStaked * SLASH_PENALTY_RATE) / 10000;

    //     emit ValidatorSlashed(penaltyAmount, timestamp);
    // }

    // Emergency functions
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }

    function handleSlashing(uint256 slashAmount) external override {}

    function addOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(OPERATOR_ROLE, operator);
    }

    function removeOperator(address operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(OPERATOR_ROLE, operator);
    }

    function totalAssets() public view returns (uint256) {
        (uint256 currentRewards, uint256 timestamp) = oracle.getCurrentRewards();
        rewardPool = currentRewards;
        return totalStaked + currentRewards;
    }

    function asset() public pure returns (address) {
        return address(0); // Native token
    }
}