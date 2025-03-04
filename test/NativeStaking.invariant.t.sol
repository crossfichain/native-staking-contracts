// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "./NativeStaking.base.t.sol";
// import "./handlers/StakingHandler.t.sol";

// contract NativeStakingInvariantTest is NativeStakingBaseTest {
//     StakingHandler public handler;

//     function setUp() public override {
//         super.setUp();
//         handler = new StakingHandler(staking);
        
//         // Target the handler contract for invariant testing
//         targetContract(address(handler));

//         // Label functions that can be called during invariant testing
//         bytes4[] memory selectors = new bytes4[](4);
//         selectors[0] = handler.stake.selector;
//         selectors[1] = handler.unstake.selector;
//         // selectors[2] = handler.distributeRewards.selector;
//         // selectors[3] = handler.handleSlashing.selector;

//         targetSelector(FuzzSelector({
//             addr: address(handler),
//             selectors: selectors
//         }));
//     }

//     function invariant_totalSharesShouldMatchStaked() public {
//         // Total shares should always match total staked for initial stakes
//         if (staking.totalShares() > 0) {
//             assertApproxEqRel(
//                 staking.totalStaked(),
//                 staking.totalShares(),
//                 1e16 // 1% tolerance
//             );
//         }
//     }

//     function invariant_rewardPoolNeverNegative() public {
//         assertTrue(staking.rewardPool() >= 0, "Reward pool should never be negative");
//     }

//     function invariant_totalStakedMatchesSum() public {
//         uint256 sumOfStakes;
//         address[] memory actors = handler.getActors();
        
//         for(uint256 i = 0; i < actors.length; i++) {
//             (uint256 staked, , , ) = staking.getStakingPosition(actors[i]);
//             sumOfStakes += staked;
//         }
        
//         assertEq(staking.totalStaked(), sumOfStakes, "Total staked should match sum of positions");
//     }

//     function invariant_collateralRatioMaintained() public {
//         address[] memory actors = handler.getActors();
        
//         for(uint256 i = 0; i < actors.length; i++) {
//             (uint256 staked, uint256 collateral, , ) = staking.getStakingPosition(actors[i]);
//             if(staked > 0) {
//                 uint256 expectedCollateral = staking.exposed_calculateDelegatedAmount(staked);
//                 assertApproxEqRel(
//                     collateral,
//                     expectedCollateral,
//                     1e16 // 1% tolerance
//                 );
//             }
//         }
//     }

//     function invariant_slashingStateConsistency() public {
//         if(staking.slashingActive()) {
//             assertTrue(handler.getSlashingCount() > 0, "Slashing count should be positive when active");
//         } else {
//             assertEq(handler.getSlashingCount(), 0, "Slashing count should be zero when inactive");
//         }
//     }

//     function invariant_mathRoundingNeverReverts() public {
//         // Verify that share calculations never revert
//         assertTrue(handler.getFailedMathOperations() == 0, "Math operations should never fail");
//     }

//     function invariant_callSummary() public view {
//         handler.callSummary();
//     }
// } 