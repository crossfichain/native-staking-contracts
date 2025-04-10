# Deployment Guide

This guide provides step-by-step instructions for deploying the Native Staking contracts to various environments.

## Prerequisites

Before deploying the contracts, ensure you have:

1. **Development Environment**
   - [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
   - Git for version control
   - Node.js 16+ (for optional script support)

2. **Private Keys and Accounts**
   - Deployer account with sufficient funds (for gas)
   - Addresses for role assignments:
     - Admin address
     - Manager address
     - Operator address

3. **RPC Endpoints**
   - RPC URL for the target network
   - Archive node access for historical data (recommended)

## Environment Setup

Set up your environment variables in a `.env` file:

```bash
# Deployment Private Key (without 0x prefix)
DEV_PRIVATE_KEY=your_private_key_without_0x_prefix

# Time Intervals (seconds)
MIN_STAKE_INTERVAL=3600       # 1 hour (default for production)
MIN_UNSTAKE_INTERVAL=86400    # 1 day (default for production)
MIN_CLAIM_INTERVAL=43200      # 12 hours (default for production)

# Network
RPC_URL=https://your-rpc-node-url
```

For development and testing, you can use shorter time intervals:

```bash
MIN_STAKE_INTERVAL=30
MIN_UNSTAKE_INTERVAL=30
MIN_CLAIM_INTERVAL=30
```

## Deployment Steps

### 1. Development Deployment

For local development or testing environments:

```bash
# Start a local Anvil node (in a separate terminal)
anvil

# Deploy contracts
forge script script/DeployNativeStakingDev.s.sol:DeployNativeStakingDev --broadcast --rpc-url http://localhost:8545 -vvv
```

### 2. Testnet Deployment

For deployment to public testnets:

```bash
# Deploy to testnet (e.g., Sepolia)
forge script script/DeployNativeStakingDev.s.sol:DeployNativeStakingDev --broadcast --rpc-url $RPC_URL -vvv
```

### 3. Production Deployment

For production deployments, use a more secure approach:

```bash
# 1. Create the deployment transaction without broadcasting
forge script script/DeployNativeStakingDev.s.sol:DeployNativeStakingDev --create --rpc-url $RPC_URL -vvv

# 2. Review the transaction details
# 3. Sign and broadcast the transaction using a hardware wallet or multi-sig
```

## Deployment Process Details

The `DeployNativeStakingDev.s.sol` script performs the following steps:

1. **Deploy Supporting Contracts**
   - Deploy MockDIAOracle (for development) or connect to real DIA Oracle (for production)
   - Deploy UnifiedOracle implementation
   - Deploy NativeStaking implementation
   - Deploy ProxyAdmin for managing the proxies

2. **Deploy and Initialize Proxies**
   - Deploy Oracle Proxy with initialization data
   - Deploy NativeStaking Proxy with initialization data

3. **Configure Contract Parameters**
   - Set minimum stake, unstake, and claim intervals
   - Set XFI and MPX prices
   - Set initial validators

4. **Assign Roles**
   - Grant roles to specified addresses:
     - MANAGER_ROLE
     - OPERATOR_ROLE
     - DEFAULT_ADMIN_ROLE

5. **Verify Deployment**
   - Output deployment summary with all contract addresses
   - Log configuration parameters for reference

## Contract Addresses

After deployment, the script outputs important contract addresses:

```
--- Deployment Summary ---
MockDiaOracle address: 0x...
Oracle implementation address: 0x...
NativeStaking implementation address: 0x...
ProxyAdmin address: 0x...
Oracle Proxy address: 0x...
NativeStaking Proxy address: 0x...
```

**IMPORTANT:** Only interact with the proxy addresses, not the implementation addresses directly.

## Post-Deployment Steps

After successful deployment, perform these additional steps:

### 1. Contract Verification

Verify the contracts on the block explorer:

```bash
# Verify NativeStaking implementation
forge verify-contract <implementation_address> src/core/NativeStaking.sol:NativeStaking --chain <chain_id> --watch

# Verify Oracle implementation
forge verify-contract <implementation_address> src/periphery/UnifiedOracle.sol:UnifiedOracle --chain <chain_id> --watch
```

### 2. Frontend Integration

Update frontend applications with the new contract addresses:

```javascript
const NATIVE_STAKING_ADDRESS = "0x..."; // NativeStaking Proxy address
const ORACLE_ADDRESS = "0x...";         // Oracle Proxy address
```

### 3. Backend Setup

Configure the backend service to:
- Monitor contract events
- Process two-step operations
- Manage operator keys securely

### 4. Security Audits

For production deployments:
- Conduct security audits of the deployed contracts
- Verify the initialization parameters
- Confirm role assignments are correct

## Advanced Deployment Options

### Custom Validators

To deploy with a custom set of validators, modify the `validatorIds` array in the deployment script:

```solidity
// Initialize validator IDs
validatorIds.push("mxvaloper1your_validator_id");
// Add more validators as needed
```

### Custom Role Addresses

To use different addresses for roles, modify the constants in the deployment script:

```solidity
address constant ADMIN_ADDRESS = 0xYourAdminAddress;
address constant MANAGER_ADDRESS = 0xYourManagerAddress;
address constant OPERATOR_ADDRESS = 0xYourOperatorAddress;
```

### Production Oracle

For production, replace the MockDIAOracle with a real DIA Oracle:

```solidity
// Instead of deploying a mock
// MockDIAOracle mockDiaOracle = new MockDIAOracle();

// Use the real DIA Oracle address
address diaOracleAddress = 0xRealDIAOracleAddress;

// Pass this address to the Oracle initialization
bytes memory oracleInitData = abi.encodeWithSelector(
    UnifiedOracle.initialize.selector,
    diaOracleAddress,
    deployerAddress
);
```

## Upgrading Contracts

If you need to upgrade contracts in the future:

1. Deploy the new implementation:
```bash
forge create src/core/NativeStakingV2.sol:NativeStakingV2 --rpc-url $RPC_URL
```

2. Update the proxy to point to the new implementation:
```solidity
// Using the ProxyAdmin
proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(nativeStakingProxyAddress)), newImplementationAddress);
```

## Troubleshooting

### Common Deployment Issues

1. **Insufficient Gas**
   - Ensure the deployer account has sufficient funds

2. **RPC Connection Problems**
   - Verify the RPC URL is correct and accessible
   - Try with a different RPC provider

3. **Transaction Underpriced**
   - Increase gas price/limit in Foundry config

4. **Failed Initialization**
   - Check that constructor and initialize parameters are correct
   - Verify that addresses are valid

5. **Role Assignment Failures**
   - Ensure the deployer has the admin role before granting roles to others

For additional assistance, refer to the [Foundry documentation](https://book.getfoundry.sh/) or contact the development team. 