# Native Staking E2E Tests

This directory contains end-to-end tests for the native staking contracts, covering various features and scenarios.

## Test Files

- `E2EAdminOperationsTest.sol`: Tests for admin operations such as freezing unstaking, changing limits, etc.
- `E2EEdgeCasesTest.sol`: Tests for edge cases like minimum/maximum amounts, slashing, recovery scenarios.
- `E2ENativeTokenTest.sol`: Tests for operations using native tokens (ETH/XFI).
- `E2EValidatorStakingTest.sol`: Tests for validator (APR) staking operations.
- `E2EVaultStakingTest.sol`: Tests for vault (APY) staking operations.
- `E2ETestBase.sol`: Base contract with common setup for all E2E tests.
- `NativeStakingE2E.t.sol`: General E2E tests for staking operations.

## Passing Tests

- **Vault Staking**: All tests passing.
- **Validator Staking**: Partial pass.
  - `testClaimRewardsFromMultipleValidators`: Passes.
  - `testClaimAllRewardsAfterMultipleStakes`: Passes.
  - `testCompleteLifecycle` and `testMultipleUsersWithSameValidator`: Currently failing due to issues with `APRStaking.requestUnstake`.
- **Edge Cases**: All tests passing after fixes.
- **Native Token Operations**: Partial pass.
  - `testStakingWithNativeTokenPartial`: Passes.
  - Other tests fail due to issues with `WXFI.withdraw`.
- **Admin Operations**: All tests passing.
- **NativeStakingE2E**: Partial pass.
  - Passing: `testClaimAllRewardsAfterMultipleStakes`, `testClaimRewardsFromMultipleValidators`, `testCompoundingRewards`, `testErrorRecovery`, `testFullStakingFlow`, `testMultipleUsersWithRewards`.
  - Other tests fail due to issues with unstaking and native token operations.

## Known Issues

1. **`APRStaking.requestUnstake` Function Issue**: The request ID encoding and handling cause problems during the unstaking process. We've simplified the requestId format to make it more deterministic, but deeper issues remain in how requestIds are processed.

2. **Native Token Withdraw Issues**: The `WXFI.withdraw` function has limitations with the gas limit (2300 for transfers) which causes problems in test environments. We've removed the gas limit for tests, but additional adjustments are needed in the core contracts to fully support native token operations.

3. **Multiple Users with Complete Lifecycle**: Tests involving multiple users going through the complete lifecycle encounter issues with request ID handling and unstaking fulfillment.

## Recent Fixes

1. **Edge Cases Tests**: Fixed and passing. We've improved the handling of slashing scenarios and ensured proper validation of validator formats.

2. **APRStaking Request ID Format**: Simplified the format to make it more deterministic and easier to use in tests.

3. **MockWXFI Withdraw Function**: Removed the 2300 gas limit for tests to avoid issues with low-level ETH transfers.

## Running Tests

To run all E2E tests:
```bash
cd test/e2e
forge test
```

To run only the passing tests:
```bash
cd test/e2e
./run_passing_tests.sh
```

## Next Steps

1. Fix the core issues in the `APRStaking.requestUnstake` function to properly handle request IDs consistently.

2. Enhance the native token operations in the contracts to handle `ETH`/`XFI` transfers more reliably.

3. Address the validator staking lifecycle tests to ensure complete passes through the entire flow. 