// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NativeStaking.base.t.sol";

contract NativeStakingFailTest is NativeStakingBaseTest {
    // Staking failures
    function testFail_StakeZero() public {
        vm.prank(alice);
        staking.stake{value: 0}();
    }

    function testFail_StakeBelowMinimum() public {
        vm.prank(alice);
        staking.stake{value: MIN_STAKE - 1}();
    }

    function testFail_StakeWithInsufficientBalance() public {
        vm.prank(alice);
        staking.stake{value: INITIAL_BALANCE + 1}();
    }

    function testFail_StakeWhenPaused() public {
        vm.prank(emergency);
        staking.pause();

        vm.prank(alice);
        staking.stake{value: MIN_STAKE}();
    }

    // Unstaking failures
    function testFail_UnstakeZero() public {
        vm.prank(alice);
        staking.unstake(0);
    }

    function testFail_UnstakeWithoutStake() public {
        vm.prank(alice);
        staking.unstake(1 ether);
    }

    function testFail_UnstakeMoreThanStaked() public {
        vm.startPrank(alice);
        staking.stake{value: 100 ether}();
        staking.unstake(101 ether);
        vm.stopPrank();
    }

    // Reward distribution failures
    function testFail_DistributeZeroRewards() public {
        vm.prank(operator);
        staking.distributeRewards(0, 0);
    }

    function testFail_DistributeRewardsTooEarly() public {
        vm.prank(operator);
        staking.distributeRewards(1 ether, 0);
        
        // Try to distribute again before COMPOUND_PERIOD
        vm.prank(operator);
        staking.distributeRewards(1 ether, 0);
    }

    function testFail_DistributeRewardsUnauthorized() public {
        vm.prank(alice);
        staking.distributeRewards(1 ether, 0);
    }

    // Compound failures
    function testFail_CompoundWithNoRewards() public {
        vm.prank(operator);
        staking.compoundRewards();
    }

    function testFail_CompoundUnauthorized() public {
        vm.deal(address(staking), 1 ether);
        vm.prank(alice);
        staking.compoundRewards();
    }

    // Slashing failures
    function testFail_SlashUnauthorized() public {
        vm.prank(alice);
        staking.handleSlashing(1 ether, block.timestamp);
    }

    function testFail_SlashTwice() public {
        vm.startPrank(operator);
        staking.handleSlashing(1 ether, block.timestamp);
        staking.handleSlashing(1 ether, block.timestamp);
        vm.stopPrank();
    }

    // Access control failures
    function testFail_PauseUnauthorized() public {
        vm.prank(alice);
        staking.pause();
    }

    function testFail_UnpauseUnauthorized() public {
        vm.prank(emergency);
        staking.pause();

        vm.prank(alice);
        staking.unpause();
    }

    // Oracle failures
    function testFail_StakeWithZeroPrice() public {
        oracle.setPrice("XFI/USD", 0);
        
        vm.prank(alice);
        staking.stake{value: MIN_STAKE}();
    }

    // Edge case failures
    function testFail_UnstakeWithSlashingActive() public {
        vm.prank(alice);
        staking.stake{value: 100 ether}();

        vm.prank(operator);
        staking.handleSlashing(10 ether, block.timestamp);

        vm.prank(alice);
        staking.unstake(50 ether);
    }

    function testFail_ReentrancyOnUnstake() public {
        // Setup malicious contract that attempts reentrancy
        MaliciousContract attacker = new MaliciousContract(address(staking));
        vm.deal(address(attacker), 100 ether);

        // Attempt reentrancy attack
        attacker.attack();
    }
}

// Helper contract for reentrancy test
contract MaliciousContract {
    NativeStakingHarness public staking;
    bool public attacked;

    constructor(address _staking) {
        staking = NativeStakingHarness(payable(_staking));
    }

    function attack() external payable {
        staking.stake{value: 100 ether}();
        staking.unstake(50 ether);
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            staking.unstake(50 ether);
        }
    }
} 