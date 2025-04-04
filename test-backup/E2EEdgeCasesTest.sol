// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./E2ETestBase.sol";

/**
 * @title E2EEdgeCasesTest
 * @dev E2E tests for edge cases and error handling
 */
contract E2EEdgeCasesTest is E2ETestBase {
    function testEdgeCases() public {
        // Test minimum and maximum amounts, slashing scenarios
        
        // 1. Minimum stake amount test
        uint256 minStake = 50 ether; // From initialization
        
        // Pre-mint XFI tokens to user
        xfi.mint(user1, minStake * 2);
        
        // Stake a valid amount
        vm.startPrank(user1);
        xfi.approve(address(manager), minStake);
        manager.stakeAPR(minStake, VALIDATOR_ID);
        vm.stopPrank();
        
        // Setup oracle data for validator
        oracle.setValidatorStake(user1, VALIDATOR_ID, minStake);
        
        // 2. Validator slashing simulation - a simpler approach
        // Simulate slashing by reducing validator stake directly in oracle
        uint256 slashedAmount = minStake * 10 / 100; // 10% slashing
        uint256 remainingAmount = minStake - slashedAmount;
        oracle.setValidatorStake(user1, VALIDATOR_ID, remainingAmount);
        
        // Verify that validator stake is properly reduced
        vm.startPrank(admin);
        uint256 stakingAmt = aprContract.getValidatorStake(user1, VALIDATOR_ID);
        vm.stopPrank();
        
        // The on-chain stake amount doesn't change due to slashing - only oracle reflects this
        assertEq(stakingAmt, minStake, "Stake amount in contract should remain unchanged");
        
        // Get oracle's view of stake amount
        uint256 oracleViewOfStake = oracle.getValidatorStake(user1, VALIDATOR_ID);
        assertEq(oracleViewOfStake, remainingAmount, "Oracle should reflect slashed amount");
    }
    
    function testErrorRecovery() public {
        // Test recovery from error conditions
        uint256 stakeAmount = 200 ether;
        
        // Mint tokens to user
        xfi.mint(user1, stakeAmount * 2);
        
        // Get user's initial balance after additional minting
        uint256 initialBalance = xfi.balanceOf(user1);
        
        // User stakes
        vm.startPrank(user1);
        xfi.approve(address(manager), stakeAmount);
        manager.stakeAPR(stakeAmount, VALIDATOR_ID);
        vm.stopPrank();
        
        oracle.setValidatorStake(user1, VALIDATOR_ID, stakeAmount);
        
        // Attempt to claim rewards when manager has insufficient balance
        uint256 rewardAmount = 2 ether; // Small amount to avoid safety threshold issues
        oracle.setUserClaimableRewards(user1, rewardAmount);
        oracle.setUserClaimableRewardsForValidator(user1, VALIDATOR_ID, rewardAmount);
        
        // Ensure manager has insufficient balance by setting it to 0
        uint256 managerBalance = xfi.balanceOf(address(manager));
        if (managerBalance >= rewardAmount) {
            // Burn tokens if manager has too many
            vm.startPrank(admin);
            xfi.burn(address(manager), managerBalance);
            vm.stopPrank();
        }
        
        // Claim should fail
        vm.startPrank(user1);
        vm.expectRevert();
        manager.claimRewardsAPRForValidator(VALIDATOR_ID, rewardAmount);
        vm.stopPrank();
        
        // Replenish manager balance
        xfi.mint(address(manager), rewardAmount);
        
        // Claim should now succeed
        vm.startPrank(user1);
        bytes memory requestId = manager.claimRewardsAPRForValidator(VALIDATOR_ID, rewardAmount);
        vm.stopPrank();
        
        assertTrue(requestId.length > 0, "Request ID should be valid after recovery");
        assertEq(xfi.balanceOf(user1), initialBalance - stakeAmount + rewardAmount, "Reward should be received");
    }
    
    function testInvalidValidatorFormats() public {
        uint256 stakeAmount = 100 ether;
        
        // Mint tokens to user
        xfi.mint(user1, stakeAmount * 3);
        
        // Try staking with invalid validator formats
        vm.startPrank(user1);
        xfi.approve(address(manager), stakeAmount * 3);
        
        // Empty validator string
        string memory emptyValidator = "";
        vm.expectRevert("Invalid validator format: must start with 'mxva'");
        manager.stakeAPR(stakeAmount, emptyValidator);
        
        // Non-mxva prefix
        string memory invalidValidator = "invalid_validator";
        vm.expectRevert("Invalid validator format: must start with 'mxva'");
        manager.stakeAPR(stakeAmount, invalidValidator);
        
        // Valid prefix should succeed
        manager.stakeAPR(stakeAmount, VALIDATOR_ID);
        vm.stopPrank();
        
        // Check the valid stake was registered
        oracle.setValidatorStake(user1, VALIDATOR_ID, stakeAmount);
        
        // Verify the stake amount
        uint256 stakedAmount = aprContract.getValidatorStake(user1, VALIDATOR_ID);
        assertEq(stakedAmount, stakeAmount, "Stake amount should be recorded correctly");
        
        // Verify that user can't unstake more than they staked
        vm.startPrank(user1);
        vm.expectRevert();
        manager.unstakeAPR(stakeAmount + 1 ether, VALIDATOR_ID);
        vm.stopPrank();
        
        // Verify that we can recognize the validator in the user's validator list
        string[] memory validators = aprContract.getUserValidators(user1);
        bool validatorFound = false;
        
        for (uint i = 0; i < validators.length; i++) {
            // Simple string comparison
            bytes32 hash1 = keccak256(abi.encodePacked(validators[i]));
            bytes32 hash2 = keccak256(abi.encodePacked(VALIDATOR_ID));
            if (hash1 == hash2) {
                validatorFound = true;
                break;
            }
        }
        
        assertTrue(validatorFound, "Validator should be in the user's validator list");
    }
    
    function testZeroAmounts() public {
        // Test zero amounts in various operations
        vm.startPrank(user1);
        
        // Stake zero amount
        vm.expectRevert("Amount must be greater than zero");
        manager.stakeAPR(0, VALIDATOR_ID);
        
        // First do a valid stake
        uint256 stakeAmount = 100 ether;
        xfi.mint(user1, stakeAmount * 2);
        xfi.approve(address(manager), stakeAmount);
        manager.stakeAPR(stakeAmount, VALIDATOR_ID);
        
        // Setup oracle data
        oracle.setValidatorStake(user1, VALIDATOR_ID, stakeAmount);
        
        // Unstake zero amount
        vm.expectRevert("Amount must be greater than zero");
        manager.unstakeAPR(0, VALIDATOR_ID);
        
        vm.stopPrank();
    }
} 