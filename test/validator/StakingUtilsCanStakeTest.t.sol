// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "lib/forge-std/src/Test.sol";
import "../../src/libraries/StakingUtils.sol";

contract StakingUtilsCanStakeTest is Test {
    function testCanStakeAgainFixedTimeline() public {
        // Force the block.timestamp to a known value
        vm.warp(10000);
        uint256 currentTime = block.timestamp;
        
        // Test with no previous stake (lastStakeTime = 0)
        assertTrue(StakingUtils.canStakeAgain(0), "Should allow stake when no previous stake");
        
        // Test during cooldown period (30 minutes after staking)
        uint256 duringCooldown = currentTime - 30 minutes;
        assertFalse(StakingUtils.canStakeAgain(duringCooldown), 
            "Should not allow stake during cooldown period");
        
        // Test at exactly the end of cooldown (1 hour after staking)
        uint256 atCooldownEnd = currentTime - 1 hours;
        assertTrue(StakingUtils.canStakeAgain(atCooldownEnd), 
            "Should allow stake exactly at cooldown end");
        
        // Test well after cooldown (2 hours after staking)
        uint256 afterCooldown = currentTime - 2 hours;
        assertTrue(StakingUtils.canStakeAgain(afterCooldown), 
            "Should allow stake after cooldown period");
    }
    
    function testCanStakeAgainFutureStake() public {
        // Test when the last stake time is in the future (unusual case)
        uint256 futureLastStakeTime = block.timestamp + 1 days;
        assertFalse(StakingUtils.canStakeAgain(futureLastStakeTime), 
            "Should not allow stake when last stake time is in the future");
    }
} 