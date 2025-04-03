# CrossFi Native Staking Development Scripts

This directory contains simplified Foundry scripts for development and testing of the CrossFi Native Staking system. These scripts are designed to be more straightforward than the production deployment scripts, with easy-to-modify parameters directly in the scripts.

## Scripts Overview

### DevDeploy.s.sol

A simplified deployment script that deploys the entire Native Staking system including mock components.

**Usage:**
```bash
forge script script/dev/DevDeploy.s.sol:DevDeploy --rpc-url <RPC_URL> --broadcast -vvv
```

**Key Features:**
- Deploys Mock DIA Oracle for testing
- Deploys WXFI token
- Deploys and configures all core contracts
- Saves deployment info to `deployments/development-contracts.csv`
- Uses customizable constants at the top of the file

### DevSetupRoles.s.sol

Script for setting up roles in already deployed contracts.

**Usage:**
```bash
forge script script/dev/DevSetupRoles.s.sol:DevSetupRoles --rpc-url <RPC_URL> --broadcast -vvv
```

**Key Features:**
- Loads contract addresses from deployment file or environment variables
- Sets up admin, operator, treasury, and emergency roles
- Verifies that roles have been properly configured

### DevConfigureOracle.s.sol

Script for configuring the Oracle with custom parameters.

**Usage:**
```bash
forge script script/dev/DevConfigureOracle.s.sol:DevConfigureOracle --rpc-url <RPC_URL> --broadcast -vvv
```

**Key Features:**
- Sets APR, APY, unbonding period, and XFI price
- Updates both UnifiedOracle and Mock DIA Oracle
- Configures the launch timestamp

### DevVerify.s.sol

Script for verifying that contract connections are properly set up.

**Usage:**
```bash
forge script script/dev/DevVerify.s.sol:DevVerify --rpc-url <RPC_URL> -vvv
```

**Key Features:**
- Verifies all contract references
- Checks token details and Oracle configuration
- Validates that the system is properly set up

## How to Use

1. **Configure each script:**
   - Open the script file and modify the constants at the top
   - Set role addresses to match your test accounts
   - Adjust parameters like APR, APY, and unbonding period as needed

2. **Run in sequence for a full deployment:**
   ```bash
   # Step 1: Deploy the system
   forge script script/dev/DevDeploy.s.sol:DevDeploy --rpc-url http://localhost:8545 --broadcast -vvv
   
   # Step 2: Verify deployment 
   forge script script/dev/DevVerify.s.sol:DevVerify --rpc-url http://localhost:8545 -vvv
   
   # Step 3: Set up additional roles if needed
   forge script script/dev/DevSetupRoles.s.sol:DevSetupRoles --rpc-url http://localhost:8545 --broadcast -vvv
   
   # Step 4: Configure Oracle with custom values if needed
   forge script script/dev/DevConfigureOracle.s.sol:DevConfigureOracle --rpc-url http://localhost:8545 --broadcast -vvv
   ```

3. **Addresses are automatically saved:**
   - The deployment script saves all addresses to `deployments/development-contracts.csv`
   - Other scripts will automatically load addresses from this file

## Default Test Accounts

The scripts are configured to use these default test accounts:
- `ADMIN_ADDRESS = address(0x1)` - The admin who manages the system
- `OPERATOR_ADDRESS = address(0x2)` - The operator for daily operations
- `TREASURY_ADDRESS = address(0x3)` - The treasury to receive fees
- `EMERGENCY_ADDRESS = address(0x4)` - For emergency actions

When running on Anvil/Hardhat, these addresses can be funded using:
```bash
cast send --value 1ether 0x1 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
cast send --value 1ether 0x2 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
cast send --value 1ether 0x3 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
cast send --value 1ether 0x4 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

## Notes

- These scripts use hard-coded values for simplicity in development, unlike the production scripts that use environment variables.
- You can easily modify the constants at the top of each file to test different configurations.
- The scripts will create a mock DIA Oracle for testing, so no external Oracle is needed.
- For local development, the scripts default to using the first Anvil private key if no `PRIVATE_KEY` environment variable is set.

# Development Deployment for CrossFi Native Staking

This directory contains a simplified script for deploying the CrossFi Native Staking system for development purposes.

## SimpleDeploy.s.sol

This is an all-in-one script for deploying the entire Native Staking system for development, including:

- Mock DIA Oracle
- WXFI token
- All core contracts with proper initialization and role setup

### Usage via Shell Script

The easiest way to deploy is using the provided shell script:

```bash
# Deploy to CrossFi dev network (default)
./script/dev/deploy.sh

# Deploy to a specific network
./script/dev/deploy.sh crossfi_test

# Deploy without verification
./script/dev/deploy.sh crossfi_dev false
```

### Direct Forge Usage

You can also run the script directly with forge:

```bash
# Using a network configuration from foundry.toml
forge script script/dev/SimpleDeploy.s.sol:SimpleDeploy --rpc-url crossfi_dev --broadcast -vvv --verify

# Using a specific RPC URL
forge script script/dev/SimpleDeploy.s.sol:SimpleDeploy --rpc-url <YOUR_RPC_URL> --broadcast -vvv
```

### Configuration

Before running, you can modify the values at the top of the script:

```solidity
// Role addresses
address public constant ADMIN = address(0xee2e617a42Aab5be36c290982493C6CC6C072982);
address public constant OPERATOR = address(0x79F9860d48ef9dDFaF3571281c033664de05E6f5);
address public constant TREASURY = address(0xee2e617a42Aab5be36c290982493C6CC6C072982);
address public constant EMERGENCY = address(0xee2e617a42Aab5be36c290982493C6CC6C072982);

// Initial configuration
uint256 public constant INITIAL_APR = 10 ether;     // 10% APR (with 18 decimals)
uint256 public constant INITIAL_APY = 8 ether;      // 8% APY (with 18 decimals)
uint256 public constant UNBONDING_PERIOD = 21 days; // 21 days (in seconds) 
uint256 public constant XFI_PRICE = 1 ether;        // $1 per XFI (with 18 decimals)
```

### How It Works

The script now deploys each contract directly:

1. Deploys a ProxyAdmin with the ADMIN as owner
2. Deploys the Mock DIA Oracle
3. Deploys WXFI Token
4. Deploys and initializes each contract with their proxies:
   - Oracle
   - APR Staking
   - APY Staking Vault
   - Staking Manager
5. Sets up all necessary roles and permissions
6. Saves the deployment information

### Output

The script will:

1. Save deployed addresses to:
   - `deployments/dev-contracts.csv` (for other scripts)
   - `deployments/dev.env` (for shell environment)

2. Display all deployed contract addresses

### After Deployment

After running the script, you can:

1. Load the environment variables:

```bash
source deployments/dev.env
```

2. Start using the contracts with the deployed addresses. 