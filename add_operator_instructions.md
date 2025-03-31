# Adding a New Operator to Native Staking Contracts

This document provides instructions for adding a new operator to the existing Native Staking contracts. The `AddOperator.s.sol` script grants all necessary roles to the new operator address across all relevant contracts.

## Prerequisite

Make sure you have the following:

1. Foundry installed on your system
2. Access to the private key that has admin roles on the existing contracts
3. RPC URL for the target network

## Contract Addresses

The following contract addresses from the existing deployment will be needed:

| Contract              | Address (crossfi_dev)                       |
|-----------------------|-------------------------------------------|
| Oracle                | 0xA0fC597d189697314843FA31fAde7814f0D47947 |
| Native Staking        | 0xc8006f0a87dAafbdB01b88B2Db4f43D53c84fDAe |
| Native Staking Vault  | 0x73b12fD8a775Ddf14e5FE5bc4f75fd69A1e2d422 |
| Native Staking Manager| 0x99242AA24DeAfd07d5d56183be5Fe092e914bEb9 |

## New Operator Address

The script is configured to add the following operator address:
`0xc35e04979A78630F16e625902283720681f2932e`

## Step-by-Step Instructions

1. Create a `.env` file in the root of the project with the following variables:

```
PRIVATE_KEY=your_private_key_here
ORACLE_ADDRESS=0xA0fC597d189697314843FA31fAde7814f0D47947
NATIVE_STAKING_ADDRESS=0xc8006f0a87dAafbdB01b88B2Db4f43D53c84fDAe
NATIVE_STAKING_VAULT_ADDRESS=0x73b12fD8a775Ddf14e5FE5bc4f75fd69A1e2d422
NATIVE_STAKING_MANAGER_ADDRESS=0x99242AA24DeAfd07d5d56183be5Fe092e914bEb9
```

2. Run the script using the following command:

```bash
# For a dry run (simulation only)
forge script script/AddOperator.s.sol:AddOperator --rpc-url <RPC_URL> -vvv

# For actual execution
forge script script/AddOperator.s.sol:AddOperator --rpc-url <RPC_URL> --broadcast -vvv
```

Replace `<RPC_URL>` with the appropriate RPC endpoint for your target network.

## Roles Granted

The script grants the new operator the following roles:

1. On the Oracle contract:
   - DEFAULT_ADMIN_ROLE
   - ORACLE_UPDATER_ROLE
   - PAUSER_ROLE
   - EMERGENCY_ROLE

2. On the Native Staking contract:
   - DEFAULT_ADMIN_ROLE
   - STAKING_MANAGER_ROLE
   - PAUSER_ROLE
   - EMERGENCY_ROLE

3. On the Native Staking Vault contract:
   - DEFAULT_ADMIN_ROLE
   - STAKING_MANAGER_ROLE
   - PAUSER_ROLE
   - EMERGENCY_ROLE
   - COMPOUNDER_ROLE

4. On the Native Staking Manager contract:
   - DEFAULT_ADMIN_ROLE
   - FULFILLER_ROLE
   - PAUSER_ROLE
   - EMERGENCY_ROLE

## Verification

After running the script, you can verify that the roles were granted correctly by checking the events emitted during the transaction or by querying the `hasRole` function on each contract for the new operator address. 