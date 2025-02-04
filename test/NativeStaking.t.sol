// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NativeStaking.base.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract NativeStakingTest is NativeStakingBaseTest {
    function testInitialState() public {
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.totalShares(), 0);
        assertEq(staking.rewardPool(), 0);
        assertFalse(staking.slashingActive());
    }

    function testStake() public {
        vm.startPrank(alice);
        
        uint256 stakeAmount = 100 ether;
        uint256 expectedShares = stakeAmount; // 1:1 for first stake

        vm.expectEmit(true, false, false, true);
        emit Staked(alice, stakeAmount, staking.exposed_calculateDelegatedAmount(stakeAmount));
        
        staking.stake{value: stakeAmount}();

        (uint256 lockedAmount, uint256 collateralAmount, uint256 shares, ) = 
            staking.getStakingPosition(alice);

        assertEq(lockedAmount, stakeAmount);
        assertEq(shares, expectedShares);
        assertEq(staking.totalStaked(), stakeAmount);
        assertEq(staking.totalShares(), expectedShares);

        vm.stopPrank();
    }

    function testPrivateConvertToShares() public {
        uint256 assets = 100 ether;
        
        // Test with empty vault
        uint256 shares = staking.exposed_convertToShares(
            assets,
            Math.Rounding.Floor
        );
        assertEq(shares, assets, "First stake should convert 1:1");

        // Add initial stake to test with non-empty vault
        vm.prank(alice);
        staking.stake{value: 100 ether}();

        shares = staking.exposed_convertToShares(
            assets,
            Math.Rounding.Floor
        );
        assertEq(shares, assets, "Should maintain share ratio");
    }

    // function testPrivateCalculateDelegatedAmount() public {
    //     uint256 amount = 100 ether;
    //     uint256 expectedDelegated = amount * staking.exposed_getNativeTokenPrice() / 
    //         staking.DELEGATED_TOKEN_PRICE();
        
    //     uint256 delegated = staking.exposed_calculateDelegatedAmount(amount);
    //     assertEq(delegated, expectedDelegated, "Incorrect delegated amount");
    // }

    function testStakingScenarios() public {
        // Test minimum stake requirement
        vm.startPrank(alice);
        vm.expectRevert("NativeStaking: Below minimum stake");
        staking.stake{value: MIN_STAKE - 1}();

        // Test successful stake
        staking.stake{value: MIN_STAKE}();

        // Test multiple stakes from same user
        staking.stake{value: MIN_STAKE}();

        // Test stake when paused
        vm.stopPrank();
        vm.prank(emergency);
        staking.pause();

        vm.expectRevert("Pausable: paused");
        vm.prank(alice);
        staking.stake{value: MIN_STAKE}();
    }

    function testUnstakingScenarios() public {
        // Setup initial stake
        vm.startPrank(alice);
        staking.stake{value: 100 ether}();

        // Test unstake more than staked
        vm.expectRevert("NativeStaking: Insufficient stake");
        staking.unstake(101 ether);

        // Test successful unstake
        uint256 balanceBefore = address(alice).balance;
        staking.unstake(50 ether);
        assertEq(address(alice).balance, balanceBefore + 50 ether);

        // Test unstake with rewards
        vm.stopPrank();
        vm.deal(address(staking), 10 ether);
        (bool success,) = address(staking).call{value: 10 ether}("");
        require(success, "Transfer failed");

        vm.prank(alice);
        uint256 balanceBeforeWithRewards = address(alice).balance;
        staking.unstake(50 ether);
        assertGt(address(alice).balance, balanceBeforeWithRewards + 50 ether);
    }

    function testRewardsScenarios() public {
        // Setup initial stakes
        vm.prank(alice);
        staking.stake{value: 100 ether}();
        vm.prank(bob);
        staking.stake{value: 100 ether}();

        // Test reward distribution
        vm.startPrank(operator);
        vm.expectRevert("NativeStaking: Too early");
        staking.distributeRewards(10 ether, 1 ether);

        // Move time forward
        vm.warp(block.timestamp + staking.COMPOUND_PERIOD());
        
        staking.distributeRewards(10 ether, 1 ether);
        assertEq(staking.rewardPool(), 10 ether);

        // Test compounding
        staking.compoundRewards();
        assertEq(staking.rewardPool(), 0);
        vm.stopPrank();
    }

    function testSlashingScenarios() public {
        // Setup initial stake
        vm.prank(alice);
        staking.stake{value: 100 ether}();

        // Test unauthorized slashing
        vm.expectRevert();
        vm.prank(alice);
        staking.handleSlashing(10 ether, block.timestamp);

        // Test successful slashing
        vm.startPrank(operator);
        staking.handleSlashing(10 ether, block.timestamp);

        // Test double slashing
        vm.expectRevert("NativeStaking: Slashing already active");
        staking.handleSlashing(10 ether, block.timestamp);
        vm.stopPrank();
    }

    function testAccessControlScenarios() public {
        // Test emergency role
        vm.expectRevert();
        staking.pause();

        vm.prank(emergency);
        staking.pause();

        vm.prank(emergency);
        staking.unpause();

        // Test operator role
        vm.expectRevert();
        staking.compoundRewards();

        vm.prank(operator);
        vm.warp(block.timestamp + staking.COMPOUND_PERIOD());
        staking.distributeRewards(10 ether, 1 ether);
    }

    // Additional test functions...
} 