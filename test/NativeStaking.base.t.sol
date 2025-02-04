// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NativeStakingHarness} from "./NativeStakingHarness.sol";
import {MockDIAOracle} from "./mocks/MockDIAOracle.sol";

contract NativeStakingBaseTest is Test {
    NativeStakingHarness public staking;
    MockDIAOracle public oracle;
    
    // Test accounts
    address public owner;
    address public operator = address(0x1);
    address public emergency = address(0x2);
    address public alice = address(0x3);
    address public bob = address(0x4);
    address public carol = address(0x5);

    // Constants
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant MIN_STAKE = 50 ether;
    uint256 public constant COMPOUND_PERIOD = 2 weeks;
    uint256 public constant ORACLE_PRICE = 1 ether;

    // Events from interfaces
    event Staked(address indexed user, uint256 nativeAmount, uint256 collateralAmount);
    event Unstaked(address indexed user, uint256 nativeAmount, uint256 rewardsAmount);
    event RewardsDistributed(uint256 totalRewards, uint256 newCollateralMinted);
    event ValidatorSlashed(uint256 slashAmount, uint256 timestamp);
    event RewardsCompounded(uint256 totalNativeRewards, uint256 newCollateralAmount);

    function setUp() public virtual {
        // Setup owner
        owner = address(this);
        vm.label(owner, "Owner");
        vm.label(operator, "Operator");
        vm.label(emergency, "Emergency");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(carol, "Carol");

        // Deploy and setup oracle
        oracle = new MockDIAOracle();
        oracle.setPrice("XFI/USD", ORACLE_PRICE);

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

    function _distributeRewards(uint256 amount) internal {
        vm.prank(operator);
        staking.distributeRewards(amount, 0);
    }

    function _warpToNextCompoundPeriod() internal {
        vm.warp(block.timestamp + COMPOUND_PERIOD);
    }

    function _checkStakingPosition(
        address user,
        uint256 expectedLocked,
        uint256 expectedShares
    ) internal {
        (uint256 locked, , uint256 shares, ) = staking.getStakingPosition(user);
        assertEq(locked, expectedLocked, "Incorrect locked amount");
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
} 