# CrossFi Native Staking Integration Update

This document provides steps to update the integration documentation and add a new operator to the system.

## Adding a New Operator

The new operator address `0xc35e04979A78630F16e625902283720681f2932e` can be added to all contracts using the provided script.

### Prerequisites

1. Make sure your `.env` file contains the following variables:
   ```
   PRIVATE_KEY=<private_key_of_an_existing_admin>
   ORACLE_PROXY_ADDRESS=<oracle_proxy_address>
   APR_STAKING_PROXY_ADDRESS=<apr_staking_proxy_address>
   APY_STAKING_PROXY_ADDRESS=<apy_staking_proxy_address>
   STAKING_MANAGER_PROXY_ADDRESS=<staking_manager_proxy_address>
   ```

2. Ensure you have Foundry installed and configured.

### Running the Script

1. Execute the following command:
   ```bash
   source .env
   forge script script/AddOperator.s.sol:AddOperator --rpc-url <RPC_URL> --broadcast -vvv
   ```

2. The script will add the new operator address with the following roles:
   - DEFAULT_ADMIN_ROLE on all contracts
   - ORACLE_UPDATER_ROLE and PAUSER_ROLE on UnifiedOracle
   - EMERGENCY_ROLE on NativeStaking (APR)
   - COMPOUNDER_ROLE and EMERGENCY_ROLE on NativeStakingVault (APY)
   - FULFILLER_ROLE on NativeStakingManager

## Updating Integration Documentation

The integration documentation should be updated to include:

1. **Current Contract Addresses**:
   - Update the contract addresses section in the integration guide to match the current deployment
   - Verify addresses in the `deployments` directory

2. **Role Management**:
   - Add information about the new operator address
   - Update instructions for role validation

3. **Examples**:
   - Update code examples with current interfaces
   - Ensure function calls reflect the current contract methods

4. **Translation**:
   - The current integration guide (`Integration-Guide.md`) includes non-English characters that should be replaced with proper English text
   - Fix encoding issues in the existing document

## Verifying System State

Before updating documentation, verify the current state of the system by running:

```bash
source .env
forge script script/deployment/VerifyDeployment.s.sol:VerifyDeployment --rpc-url <RPC_URL>
```

This will show the current settings and configuration of all contracts.

## Recommended Updates for Integration Guide

1. Contract addresses section:
   ```
   ## Contract Addresses
   
   The following contract addresses should be used for integration:
   
   ```
   WXFI_ADDRESS=<current_address>
   ORACLE_PROXY_ADDRESS=<current_address>
   APR_STAKING_PROXY_ADDRESS=<current_address>
   APY_STAKING_PROXY_ADDRESS=<current_address>
   STAKING_MANAGER_PROXY_ADDRESS=<current_address>
   ```
   ```

2. Operator information:
   ```
   ## Operator Addresses
   
   The system has the following operators:
   - Operator 1: <address1>
   - Operator 2: <address2>
   - Operator 3: 0xc35e04979A78630F16e625902283720681f2932e
   
   These operators have administrative privileges on the staking contracts.
   ```

3. Backend event handling:
   ```javascript
   // Example of monitoring events
   stakingManager.on("StakedAPR", (user, amount, mpxAmount, validator, requestId, event) => {
     console.log(`New stake from ${user}: ${ethers.utils.formatEther(amount)} XFI`);
     console.log(`Request ID: ${requestId}`);
     // Save information to database
   });
   ``` 