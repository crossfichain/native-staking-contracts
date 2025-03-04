// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "./NativeStaking.base.t.sol";
// import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// contract NativeStakingTest is NativeStakingBaseTest {
//     function testInitialState() public view {
//         assertEq(staking.totalStaked(), 0);
//         assertEq(staking.totalShares(), 0);
//         assertFalse(staking.slashingActive());
//     }

//     function testStake() public {
//         vm.startPrank(alice);
        
//         uint256 stakeAmount = 100 ether;
//         uint256 expectedShares = stakeAmount; // 1:1 for first stake
//         uint256 expectedDelegated = _calculateExpectedDelegated(stakeAmount);

//         vm.expectEmit(true, false, false, true);
//         emit Staked(alice, stakeAmount, expectedDelegated);
        
//         staking.stake{value: stakeAmount}();

//         (uint256 lockedAmount, uint256 collateralAmount, uint256 shares, ) = 
//             staking.getStakingPosition(alice);

//         assertEq(lockedAmount, stakeAmount);
//         assertEq(collateralAmount, expectedDelegated);
//         assertEq(shares, expectedShares);
//         assertEq(staking.totalStaked(), stakeAmount);
//         assertEq(staking.totalShares(), expectedShares);
//         assertTrue(staking.isStaker(alice));

//         vm.stopPrank();
//     }

//     function testMultipleStakes() public {
//         // First stake
//         vm.startPrank(alice);
//         uint256 firstStake = 100 ether;
//         staking.stake{value: firstStake}();
//         vm.stopPrank();

//         // Second stake from different user
//         vm.startPrank(bob);
//         uint256 secondStake = 50 ether;
//         staking.stake{value: secondStake}();
//         vm.stopPrank();

//         // Verify total staked and shares
//         assertEq(staking.totalStaked(), firstStake + secondStake);
//         assertEq(staking.totalShares(), firstStake + secondStake);

//         // Verify individual positions
//         (uint256 aliceLocked,,uint256 aliceShares,) = staking.getStakingPosition(alice);
//         (uint256 bobLocked,,uint256 bobShares,) = staking.getStakingPosition(bob);

//         assertEq(aliceLocked, firstStake);
//         assertEq(aliceShares, firstStake);
//         assertEq(bobLocked, secondStake);
//         assertEq(bobShares, secondStake);
//     }

//     function testCompoundRewards() public {
//         // Setup initial stakes
//         vm.startPrank(alice);
//         staking.stake{value: 100 ether}();
//         vm.stopPrank();
        
//         vm.startPrank(bob);
//         staking.stake{value: 100 ether}();
//         vm.stopPrank();

//         uint256 rewardAmount = 10 ether;
//         uint256 expectedDelegated = _calculateExpectedDelegated(rewardAmount);

//         // Set rewards in oracle
//         oracle.setRewards(rewardAmount);

//         // Test compound rewards
//         vm.startPrank(operator);
//         vm.expectEmit(true, false, false, true);
//         emit RewardsCompounded(rewardAmount, expectedDelegated);
        
//         staking.compoundRewards{value: rewardAmount}();

//         // Verify rewards were distributed equally
//         (uint256 aliceLockedAmount,,, ) = staking.getStakingPosition(alice);
//         (uint256 bobLockedAmount,,, ) = staking.getStakingPosition(bob);
        
//         assertEq(aliceLockedAmount, 105 ether); // 100 + (10/2)
//         assertEq(bobLockedAmount, 105 ether);   // 100 + (10/2)
        
//         vm.stopPrank();
//     }

//     function testUnstake() public {
//         // Setup initial stake
//         vm.startPrank(alice);
//         staking.stake{value: 100 ether}();

//         uint256 balanceBefore = address(alice).balance;
        
//         // Set some rewards
//         vm.stopPrank();
//         uint256 rewardAmount = 10 ether;
//         oracle.setRewards(rewardAmount);
//         vm.prank(operator);
//         staking.compoundRewards{value: rewardAmount}();

//         // Test unstake
//         vm.startPrank(alice);
//         vm.expectEmit(true, false, false, false);
//         emit Unstaked(alice, 50 ether, 5 ether); // Half stake + half rewards
        
//         staking.unstake(50 ether);
//         assertEq(address(alice).balance, balanceBefore + 50 ether);

//         (uint256 lockedAmount,, uint256 shares, ) = 
//             staking.getStakingPosition(alice);

//         assertEq(lockedAmount, 100 ether + 10 ether - 50 ether);
//         assertEq(shares, 50 ether);
//         vm.stopPrank();
//     }

//     function testPartialUnstakeWithRewards() public {
//         // Initial stake
//         vm.startPrank(alice);
//         staking.stake{value: 100 ether}();
//         vm.stopPrank();

//         // Add rewards
//         uint256 rewardAmount = 20 ether;
//         oracle.setRewards(rewardAmount);
//         vm.prank(operator);
//         staking.compoundRewards{value: rewardAmount}();

//         // Unstake 25% of position
//         vm.startPrank(alice);
//         uint256 unstakeAmount = 30 ether; // 25% of 120 ether total
//         uint256 balanceBefore = address(alice).balance;
        
//         staking.unstake(unstakeAmount);
        
//         // Check balances and position
//         assertEq(address(alice).balance, balanceBefore + unstakeAmount);
//         (uint256 remainingLocked,, uint256 remainingShares,) = staking.getStakingPosition(alice);
//         assertEq(remainingLocked, 90 ether); // 120 - 30
//         assertEq(remainingShares, 70 ether); // 100 - 30

//         // Check price per share delta
//         uint256 pricePerShareBefore = 1.2 ether; // 120 total / 100 shares
//         uint256 pricePerShareAfter = remainingLocked * 1e18 / remainingShares; // 90 / 70 ~= 1.285714...
//         assertGt(pricePerShareAfter, pricePerShareBefore, "Price per share should increase after partial unstake");
        
//         vm.stopPrank();
//     }

//     function testStakingScenarios() public {
//         // Test minimum stake requirement
//         vm.startPrank(alice);
//         vm.expectRevert("NativeStaking: Below minimum stake");
//         staking.stake{value: 49 ether}(); // MIN_STAKE is 50 ether

//         // Test successful stake
//         staking.stake{value: 50 ether}();

//         // Test multiple stakes from same user
//         staking.stake{value: 50 ether}();

//         // Test stake when paused
//         vm.stopPrank();
//         vm.prank(emergency);
//         staking.pause();

//         vm.expectRevert(Pausable.EnforcedPause.selector);
//         vm.prank(alice);
//         staking.stake{value: 50 ether}();
//     }

//     function testAccessControlScenarios() public {
//         address newOperator = address(0x123);
        
//         // Test operator management
//         vm.startPrank(admin);
//         staking.addOperator(newOperator);
//         assertTrue(staking.hasRole(staking.OPERATOR_ROLE(), newOperator));
        
//         staking.removeOperator(newOperator);
//         assertFalse(staking.hasRole(staking.OPERATOR_ROLE(), newOperator));
//         vm.stopPrank();

//         // Test emergency role
//         vm.expectRevert();
//         staking.pause();

//         vm.prank(emergency);
//         staking.pause();

//         vm.prank(emergency);
//         staking.unpause();

//         // Test operator role
//         vm.expectRevert();
//         staking.compoundRewards();

//         uint256 rewardAmount = 10 ether;
//         oracle.setRewards(rewardAmount);
//         vm.startPrank(operator);
//         staking.compoundRewards{value: rewardAmount}();
//         vm.stopPrank();
//     }

//     function testPriceConversion() public {
//         // Test price conversion with different amounts
//         uint256[] memory amounts = new uint256[](3);
//         amounts[0] = 100 ether;
//         amounts[1] = 1000 ether;
//         amounts[2] = 10000 ether;

//         for (uint256 i = 0; i < amounts.length; i++) {
//             uint256 delegatedAmount = _calculateExpectedDelegated(amounts[i]);
//             assertTrue(delegatedAmount > 0, "Delegated amount should be positive");
//             assertTrue(
//                 delegatedAmount > amounts[i],
//                 "Delegated amount should be greater than native amount"
//             );
//         }
//     }

//     function testRewardsDistribution() public {
//         // Setup stakes with different proportions
//         _stake(alice, 100 ether); // 50%
//         _stake(bob, 50 ether);    // 25%
//         _stake(carol, 50 ether);  // 25%

//         uint256 rewardAmount = 100 ether;
//         oracle.setRewards(rewardAmount);

//         vm.prank(operator);
//         staking.compoundRewards{value: rewardAmount}();

//         // Verify proportional distribution
//         (uint256 aliceLocked,,, ) = staking.getStakingPosition(alice);
//         (uint256 bobLocked,,, ) = staking.getStakingPosition(bob);
//         (uint256 carolLocked,,, ) = staking.getStakingPosition(carol);

//         assertEq(aliceLocked, 150 ether); // 100 + 50% of rewards
//         assertEq(bobLocked, 75 ether);    // 50 + 25% of rewards
//         assertEq(carolLocked, 75 ether);  // 50 + 25% of rewards
//     }
// } 