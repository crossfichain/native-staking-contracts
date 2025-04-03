# CrossFi Native Staking Deployment Summary

## Deployment on crossfi_dev network

### Contract Addresses

| Contract            | Address                                      |
|---------------------|--------------------------------------------|
| WXFI                | 0x5761524160a2494D69F29bf879eac26109916B33 |
| Mock DIA Oracle     | 0x6db5458D5FEe2ff5f809833FB2F337AB5eDCf13e |
| Oracle Proxy        | 0xA0fC597d189697314843FA31fAde7814f0D47947 |
| APR Staking Proxy   | 0xc8006f0a87dAafbdB01b88B2Db4f43D53c84fDAe |
| APY Staking Proxy   | 0x73b12fD8a775Ddf14e5FE5bc4f75fd69A1e2d422 |
| Staking Manager Proxy | 0x99242AA24DeAfd07d5d56183be5Fe092e914bEb9 |
| Proxy Admin         | 0x6bA9cE369b3ac285794322Dd956283eccE176C93 |

### Account Addresses

| Role               | Address                                      |
|--------------------|--------------------------------------------|
| Admin              | 0xee2e617a42Aab5be36c290982493C6CC6C072982 |
| Operator           | 0x79F9860d48ef9dDFaF3571281c033664de05E6f5 |
| Treasury           | 0xee2e617a42Aab5be36c290982493C6CC6C072982 |
| Emergency          | 0xee2e617a42Aab5be36c290982493C6CC6C072982 |
| New Operator       | 0xc35e04979A78630F16e625902283720681f2932e |

## Deployment on crossfi_test network

Failed to deploy to `crossfi_test` network due to error: "HTTP error 502 with body: No available nodes"

## Implementation Details

The deployment script `SimpleDeploy.s.sol` was updated to include the new operator address (`0xc35e04979A78630F16e625902283720681f2932e`). The following roles were granted to the new operator:

- DEFAULT_ADMIN_ROLE
- ORACLE_UPDATER_ROLE
- PAUSER_ROLE
- EMERGENCY_ROLE
- STAKING_MANAGER_ROLE
- FULFILLER_ROLE
- COMPOUNDER_ROLE
- UPGRADER_ROLE

These roles were granted across all relevant contracts: UnifiedOracle, NativeStaking, NativeStakingVault, and NativeStakingManager.

## Note

The deployment script attempted to save the addresses to `deployments/dev-contracts.csv`, but the file write operation was not permitted in the sandbox environment. 