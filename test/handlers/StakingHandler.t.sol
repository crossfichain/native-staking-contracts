// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {NativeStakingHarness} from "../NativeStakingHarness.sol";
import {console} from "forge-std/console.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {Test} from "forge-std/Test.sol";





contract StakingHandler is Test{
    NativeStakingHarness public staking;
    
    // Track actors and operations
    address[] public actors;
    mapping(address => bool) public isActor;
    uint256 public slashingCount;
    uint256 public failedMathOperations;
    
    // Constants
    uint256 public constant MIN_STAKE = 50 ether;
    uint256 public constant MAX_STAKE = 1000 ether;
    uint256 public constant COMPOUND_PERIOD = 2 weeks;

    // Operation counters for statistics
    uint256 public stakeCount;
    uint256 public unstakeCount;
    uint256 public rewardCount;

    constructor(NativeStakingHarness _staking) {
        staking = _staking;
    }

    // Handler functions
    function stake(uint256 amount) public {
        // Bound amount between MIN_STAKE and MAX_STAKE
        amount = bound(amount, MIN_STAKE, MAX_STAKE);
        
        // Create or reuse actor
        address actor = getOrCreateActor();
        vm.prank(actor);
        try staking.stake{value: amount}() {
            stakeCount++;
        } catch {
            // Track failed math operations
            failedMathOperations++;
        }
    }

    function unstake(uint256 amount) public {
        if (actors.length == 0) return;
        
        address actor = actors[bound(uint256(keccak256(abi.encode(block.timestamp))), 0, actors.length - 1)];
        (uint256 staked, , , ) = staking.getStakingPosition(actor);
        
        if (staked > 0) {
            amount = bound(amount, 0, staked);
            vm.prank(actor);
            try staking.unstake(amount) {
                unstakeCount++;
            } catch {
                failedMathOperations++;
            }
        }
    }

    // function distributeRewards(uint256 amount) public {
    //     // Skip if no stakes
    //     if (staking.totalStaked() == 0) return;
        
    //     amount = bound(amount, 0.1 ether, 10 ether);
        
    //     // Ensure enough time has passed
    //     vm.warp(block.timestamp + COMPOUND_PERIOD);
        
    //     vm.prank(staking.getRoleMember(staking.OPERATOR_ROLE(), 0));
    //     try staking.distributeRewards(amount, 0) {
    //         rewardCount++;
    //     } catch {
    //         failedMathOperations++;
    //     }
    // }

    // function handleSlashing(uint256 amount) public {
    //     // Skip if no stakes or already slashed
    //     if (staking.totalStaked() == 0 || staking.slashingActive()) return;
        
    //     amount = bound(amount, 0.1 ether, staking.totalStaked());
        
    //     vm.prank(staking.getRoleMember(staking.OPERATOR_ROLE(), 0));
    //     try staking.handleSlashing(amount, block.timestamp) {
    //         slashingCount++;
    //     } catch {
    //         failedMathOperations++;
    //     }
    // }

    // Helper functions
    function getOrCreateActor() internal returns (address) {
        if (actors.length > 0 && uint256(keccak256(abi.encode(block.timestamp))) % 2 == 0) {
            // Reuse existing actor
            return actors[bound(uint256(keccak256(abi.encode(block.timestamp))), 0, actors.length - 1)];
        }
        
        // Create new actor
        address actor = address(uint160(uint256(keccak256(abi.encode(block.timestamp, actors.length)))));
        if (!isActor[actor]) {
            actors.push(actor);
            isActor[actor] = true;
            vm.deal(actor, MAX_STAKE * 2);
        }
        return actor;
    }

    // View functions
    function getActors() external view returns (address[] memory) {
        return actors;
    }

    function getSlashingCount() external view returns (uint256) {
        return slashingCount;
    }

    function getFailedMathOperations() external view returns (uint256) {
        return failedMathOperations;
    }

    function callSummary() external view {
        console.log("Handler call summary:");
        console.log("Total actors:", actors.length);
        console.log("Stake operations:", stakeCount);
        console.log("Unstake operations:", unstakeCount);
        console.log("Reward distributions:", rewardCount);
        console.log("Slashing events:", slashingCount);
        console.log("Failed math operations:", failedMathOperations);
    }

    receive() external payable {}
} 