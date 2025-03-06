# CrossFi Native Staking Deployment Guide

This directory contains scripts and records for deploying the CrossFi Native Staking system to various networks.

## Prerequisites

1. Install Foundry:
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. Clone the repository:
   ```bash
   git clone https://github.com/crossfi/native-staking-contracts.git
   cd native-staking-contracts
   ```

3. Install dependencies:
   ```bash
   forge install
   ```

## Deployment Process

### 1. Set Environment Variables

Copy the `.env.example` file to `.env` and adjust the values:

```bash
cp .env.example .env
```

Required variables:
- `PRIVATE_KEY`: Your deployment private key
- `ADMIN_ADDRESS`: The admin who will manage the system
- `OPERATOR_ADDRESS`: The operator responsible for daily operations
- `TREASURY_ADDRESS`: Address to receive fees
- `EMERGENCY_ADDRESS`: Address with emergency powers
- `DIA_ORACLE_ADDRESS`: Required for production deployment

### 2. Deploy Using the Master Deployment Script

#### For Development Environment (deploys everything including mock DIA Oracle):

```bash
source .env
forge script script/deployment/MasterDeployment.s.sol:MasterDeployment --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv
```

#### For Production Environment (requires existing DIA Oracle):

```bash
source .env
export PRODUCTION=true
forge script script/deployment/MasterDeployment.s.sol:MasterDeployment --rpc-url $MAINNET_RPC_URL --broadcast -vvv
```

The master deployment script will:
1. Deploy WXFI if not provided
2. Deploy mock DIA Oracle for development or use existing one in production
3. Deploy all contracts with proper proxies
4. Set up basic roles and configuration
5. Save deployment addresses to a CSV file

### 3. Verify Deployment

After deployment, verify everything is correctly set up:

```bash
source .env
forge script script/deployment/VerifyDeployment.s.sol:VerifyDeployment --rpc-url $NETWORK_RPC_URL
```

This script checks:
- Contract connections
- Role assignments
- Oracle settings

### 4. Post-Deployment Setup

For additional role configuration:

```bash
source .env
forge script script/deployment/PostDeploymentSetup.s.sol:PostDeploymentSetup --rpc-url $NETWORK_RPC_URL --broadcast
```

This script configures:
- Operator, Treasury, and Emergency roles
- Additional Oracle parameters

## Alternative Deployment Methods

If you need more control, you can use the individual scripts:

### Individual Deployment Script

```bash
forge script script/deployment/DeploymentScript.s.sol:DeploymentScript --rpc-url $NETWORK_RPC_URL --broadcast --verify
```

## Contract Verification

All contracts should be verified on the block explorer after deployment:

```bash
forge verify-contract --chain $CHAIN_ID --constructor-args $(cast abi-encode "constructor()") $WXFI_ADDRESS src/periphery/WXFI.sol:WXFI $ETHERSCAN_API_KEY
```

For proxy contracts, verify both the implementation and proxy contracts.

## Deployment Records

Each deployment is recorded in this directory in CSV format with the following columns:
1. Network
2. Timestamp
3. Chain ID
4. WXFI Address
5. DIA Oracle Address
6. Oracle Proxy Address
7. APR Staking Proxy Address
8. APY Staking Proxy Address
9. Staking Manager Proxy Address
10. Proxy Admin Address

## Notes

- The deployment scripts use the `DeploymentCoordinator.sol` contract to ensure consistent deployment across different networks.
- For development, a mock DIA Oracle is deployed if no address is provided.
- For production, a DIA Oracle address is required.
- All role addresses (admin, operator, treasury, emergency) are required for deployment. 