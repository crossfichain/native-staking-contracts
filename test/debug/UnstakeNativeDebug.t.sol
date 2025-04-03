// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../e2e/E2ETestBase.sol";

contract UnstakeNativeDebugTest is E2ETestBase {
    function setUp() public override {
        super.setUp();
        console.log("Setting up debug test");
    }

    function testClaimUnstakeAPRNative() public {
        uint256 stakeAmount = 100 ether;
        
        // User stakes XFI
        vm.startPrank(user1);
        xfi.approve(address(manager), stakeAmount);
        manager.stakeAPR(stakeAmount, VALIDATOR_ID);
        vm.stopPrank();
        
        // Setup oracle for validator stakes
        oracle.setValidatorStake(user1, VALIDATOR_ID, stakeAmount);
        
        // Make sure APR contract has enough balance for unstaking
        xfi.mint(address(aprContract), stakeAmount);
        
        // User requests unstake
        vm.startPrank(user1);
        bytes memory unstakeId = manager.unstakeAPR(stakeAmount, VALIDATOR_ID);
        vm.stopPrank();
        
        // Fast forward past unbonding period
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1 days);
        
        // Fund manager and WXFI with plenty of ETH
        vm.deal(address(manager), stakeAmount * 10);
        vm.deal(address(xfi), stakeAmount * 10);
        
        // Log balances before claiming
        console.log("Manager ETH balance before:", address(manager).balance);
        console.log("Manager WXFI balance before:", xfi.balanceOf(address(manager)));
        console.log("User1 ETH balance before:", address(user1).balance);
        
        // User claims unstake as native tokens - wrap in try/catch to see the error
        vm.startPrank(user1);
        try manager.claimUnstakeAPRNative(unstakeId) returns (uint256 amount) {
            console.log("Claim successful, amount:", amount);
            console.log("User1 ETH balance after:", address(user1).balance);
        } catch Error(string memory reason) {
            console.log("Claim failed with reason:", reason);
        } catch (bytes memory) {
            console.log("Claim failed with no reason");
        }
        vm.stopPrank();
    }
} 