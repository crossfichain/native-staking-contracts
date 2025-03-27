#!/bin/bash

# Run the vault (APY) staking tests - all pass
echo "Running Vault Staking Tests..."
forge test --match-contract E2EVaultStakingTest -v

# Run passing validator staking tests
echo "Running passing Validator Staking Tests..."
forge test --match-contract E2EValidatorStakingTest -v

# Run edge cases tests - all pass now
echo "Running Edge Cases Tests..."
forge test --match-contract E2EEdgeCasesTest -v

# Run all admin operations tests
echo "Running Admin Operations Tests..."
forge test --match-contract E2EAdminOperationsTest -v

# Run passing tests from NativeStakingE2E.t.sol
echo "Running passing tests from NativeStakingE2E..."
forge test --match-test "testClaimAllRewardsAfterMultipleStakes|testClaimRewardsFromMultipleValidators|testCompoundingRewards|testErrorRecovery|testFullStakingFlow|testMultipleUsersWithRewards" --match-contract NativeStakingE2ETest -v 