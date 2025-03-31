# Native Staking Contracts

This repository contains the smart contracts for CrossFi's Native Staking system.

## Architecture

The Native Staking system consists of the following components:

### Core Contracts

- **NativeStakingManager** - Split into multiple contracts for size optimization:
  - `BaseNativeStakingManager`: Base functionality for stake requests and common operations
  - `SplitNativeStakingManager`: Implementation with fulfillment and interface functions
  - `NativeStakingManagerLib`: Library with utility functions and calculations
- **NativeStaking** - APR-based staking contract
- **NativeStakingVault** - APY-based staking contract with compounding
- **UnifiedOracle** - Oracle for price and rewards data

### Libraries and Utilities

- **NativeStakingManagerLib** - Utility library with common functions and calculations

### Contract Split Architecture

To avoid contract size limitations (24KB max), the `NativeStakingManager` is split into multiple contracts:

1. **BaseNativeStakingManager**: 
   - Contains core functionality and request handling
   - Inherits from OpenZeppelin's AccessControl, Pausable, etc.
   - Implements the request creation methods

2. **SplitNativeStakingManager**:
   - Inherits from BaseNativeStakingManager
   - Implements fulfillment functions 
   - Implements all interface functions

3. **NativeStakingManagerLib**:
   - Contains the StakingMode enum (APR/APY)
   - Contains validation functions
   - Contains gas calculation utilities

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Install dependencies

```bash
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy

Set the environment variables in a `.env` file:

```
DEPLOYER_PRIVATE_KEY=your_private_key
RPC_URL=your_rpc_url
```

Run the deployment script:

```bash
source .env
forge script script/dev/SimpleDeploy.s.sol:SimpleDeploy --rpc-url $RPC_URL --broadcast -vvv
```

### Verification

To verify the deployment:

```bash
forge script script/deployment/VerifyDeployment.s.sol:VerifyDeployment --rpc-url $RPC_URL -vvv
```

## License

MIT
