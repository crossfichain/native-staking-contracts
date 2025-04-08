# Native Staking Contract Deployment

This section explains how to deploy the NativeStaking contract with the provided deployment script.

## Deployment Script

The `DeployNativeStaking.s.sol` script facilitates the deployment of the Native Staking contracts with proper configuration. It sets up the following:

- Deploys the NativeStaking contract with a TransparentUpgradeableProxy
- Sets up roles for three addresses:
  - Admin: 0xee2e617a42Aab5be36c290982493C6CC6C072982
  - Manager: 0xc35e04979A78630F16e625902283720681f2932e
  - Operator: 0x79F9860d48ef9dDFaF3571281c033664de05E6f5
- Configures all time delays with either default values or custom values provided through environment variables

## Required Environment Variables

Before running the deployment script, set up the following environment variable:

```bash
export DEV_PRIVATE_KEY=your_private_key_without_0x_prefix
```

This private key will be used to:
1. Deploy all contracts
2. Initialize the contracts with the corresponding address as admin
3. Assign roles to other addresses

## Running the Deployment

To deploy with default time delay parameters:

```bash
forge script script/DeployNativeStaking.s.sol:DeployNativeStaking --broadcast -vvvv
```

To customize the time delay parameters:

```bash
forge script script/DeployNativeStaking.s.sol:DeployNativeStaking --broadcast -vvvv \
  --env MIN_STAKE_INTERVAL=3600 \
  --env MIN_UNSTAKE_INTERVAL=86400 \
  --env MIN_CLAIM_INTERVAL=43200
```

Replace the values with your desired time intervals in seconds.

## Default Time Parameters

- MIN_STAKE_INTERVAL: 1 hour (3600 seconds)
- MIN_UNSTAKE_INTERVAL: 1 day (86400 seconds)
- MIN_CLAIM_INTERVAL: 12 hours (43200 seconds)

## For Testing on a Dev Network

To deploy on a local or development network:

```bash
forge script script/DeployNativeStaking.s.sol:DeployNativeStaking --broadcast --rpc-url http://localhost:8545 -vvvv
```

For a public testnet (like Sepolia):

```bash
forge script script/DeployNativeStaking.s.sol:DeployNativeStaking --broadcast --rpc-url $RPC_URL -vvvv
```

## Important Notes on Roles

- The deployer address (derived from DEV_PRIVATE_KEY) will be the initial admin
- The script will assign Manager role to MANAGER_ADDRESS
- The script will assign Operator role to OPERATOR_ADDRESS
- If the deployer address is different from ADMIN_ADDRESS, the script will also grant admin role to ADMIN_ADDRESS

## Notes

- The script deploys a mock Oracle for testing purposes. In production, you'll need to connect to a real Oracle.
- The deployment uses the Transparent Proxy pattern to allow for future upgrades.
- After deployment, all specified addresses can manage their respective roles directly through the contract. 