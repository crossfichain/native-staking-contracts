// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NativeStakingHarness} from "./NativeStakingHarness.sol";
import {MockUnifiedOracle} from "./mocks/MockUnifiedOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract NativeStakingBaseTest is Test {
    using Math for uint256;

    NativeStakingHarness public staking;
    MockUnifiedOracle public oracle;
    
    // Test accounts
    address public admin;
    address public operator = address(0x1);
    address public emergency = address(0x2);
    address public alice = address(0x3);
    address public bob = address(0x4);
    address public carol = address(0x5);

    // Constants
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant MIN_STAKE = 50 ether;
    uint256 public constant COMPOUND_PERIOD = 2 weeks;
    uint256 public constant ORACLE_PRICE = 1 ether; // 1 USD in 18 decimals
    uint256 public constant DELEGATED_TOKEN_PRICE = 0.04 ether; // 0.04 USD in 18 decimals

    // Events from interfaces
    event Staked(address indexed user, uint256 nativeAmount, uint256 collateralAmount);
    event Unstaked(address indexed user, uint256 nativeAmount, uint256 rewardsAmount);
    event RewardsCompounded(uint256 totalNativeRewards, uint256 newCollateralAmount);

    function setUp() public virtual {
        // Setup admin
        admin = address(this);
        vm.label(admin, "Admin");
        vm.label(operator, "Operator");
        vm.label(emergency, "Emergency");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(carol, "Carol");

        // Deploy and setup mock oracle
        oracle = new MockUnifiedOracle();
        oracle.setXFIPrice(ORACLE_PRICE);

        // Deploy staking contract
        staking = new NativeStakingHarness(
            address(oracle),
            operator,
            emergency
        );

        // Setup initial balances
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(carol, INITIAL_BALANCE);
        vm.deal(operator, INITIAL_BALANCE);
    }

    // Helper functions
    function _stake(address user, uint256 amount) internal {
        vm.prank(user);
        staking.stake{value: amount}();
    }

    function _compoundRewards(uint256 amount) internal {
        oracle.setRewards(amount);
        vm.prank(operator);
        staking.compoundRewards{value: amount}();
    }

    function _checkStakingPosition(
        address user,
        uint256 expectedLocked,
        uint256 expectedCollateral,
        uint256 expectedShares
    ) internal view {
        (uint256 locked, uint256 collateral, uint256 shares, ) = staking.getStakingPosition(user);
        assertEq(locked, expectedLocked, "Incorrect locked amount");
        assertEq(collateral, expectedCollateral, "Incorrect collateral amount");
        assertEq(shares, expectedShares, "Incorrect shares amount");
    }

    function _getStakingPosition(address user) internal view returns (
        uint256 locked,
        uint256 collateral,
        uint256 shares,
        uint256 rewards
    ) {
        return staking.getStakingPosition(user);
    }

    function _calculateExpectedDelegated(uint256 nativeAmount) internal pure returns (uint256) {
        return (nativeAmount * ORACLE_PRICE) / DELEGATED_TOKEN_PRICE;
    }
} 