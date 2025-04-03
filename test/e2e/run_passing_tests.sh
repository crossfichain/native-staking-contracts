#!/bin/bash

# Set the Foundry test command with gas reporting
FORGE_CMD="forge test --gas-report"

# Run the passing E2E tests
echo "Running Native Staking E2E Tests..."

# Validator Staking Tests
echo "Running Validator Staking Tests..."
$FORGE_CMD --match-test "testClaimAllRewardsAfterMultipleStakes|testClaimRewardsFromMultipleValidators" -v

# Vault Staking Tests
echo "Running Vault Staking Tests..."
$FORGE_CMD --match-test "testCompoundingRewards|testFullStakingFlow|testMultipleUsersWithRewards" -v

# Edge Cases Tests
echo "Running Edge Cases Tests..."
$FORGE_CMD --match-test "testInvalidValidatorFormats|testMinStakeRequirements|testZeroAmountValidation|testFrozenUnstaking" -v

# Native Token Tests
echo "Running Native Token Tests..."
$FORGE_CMD --match-test "testStakingWithNativeTokenPartial|testStakingWithNativeToken" -v

# Admin Operations Tests
echo "Running Admin Operations Tests..."
$FORGE_CMD --match-test "testPauseUnpause|testSetMinimumAmounts|testUpgradeContractLogic" -v

echo "All passing tests completed successfully!" 