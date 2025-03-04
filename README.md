# CrossFi Native Staking Contracts

This repository contains the smart contracts for CrossFi's Native Staking system, which allows users to stake XFI tokens through two different models:

1. **APR Model (Direct Staking)** - Users stake XFI, specify validators, and earn rewards based on a simple interest model
2. **APY Model (Compounding Vault)** - Users stake XFI in a vault (ERC-4626 compliant) and earn compounding rewards

## Architecture

The system is built with a modular architecture that consists of:

### Core Contracts

- **NativeStakingManager**: Central router for all staking operations, handling both native XFI and wrapped XFI (WXFI)
- **NativeStaking**: Implements the APR staking model with direct validator delegation
- **NativeStakingVault**: Implements the APY staking model following the ERC-4626 standard

### Periphery Contracts

- **CrossFiOracle**: Provides price data and validator information from the Cosmos chain
- **WXFI**: Wrapped XFI implementation that allows native XFI to be used as an ERC20 token

### Deployment

- **DeploymentCoordinator**: Helper contract for deploying the entire system with proper proxy setup

## Technical Features

- **Upgradeable Contracts**: All core contracts use the TransparentUpgradeableProxy pattern
- **Role-Based Access Control**: Granular permissions system using OpenZeppelin's AccessControl
- **Security Measures**: Reentrancy protection, pause functionality, and other security best practices
- **ERC-4626 Compliance**: The vault follows the standard for tokenized vaults

## Contract Interactions

![System Architecture](https://crossfi.org/docs/native-staking-architecture.png)

- Users interact primarily with the NativeStakingManager contract
- The manager routes staking operations to the appropriate staking contract
- The oracle provides price and validator data from the Cosmos chain
- WXFI allows for wrapping/unwrapping of native XFI

## Development

### Prerequisites

- [Foundry](https://getfoundry.sh/)
- Node.js and npm

### Installation

```bash
git clone https://github.com/crossfi/native-staking-contracts.git
cd native-staking-contracts
forge install
npm install
```

### Compile Contracts

```bash
forge build
```

### Run Tests

```bash
forge test
```

### Deploy

For local deployment:

```bash
npm run deploy:anvil
```

For testnet deployment:

```bash
export RPC_URL=<your-rpc-url>
export ETHERSCAN_API_KEY=<your-etherscan-key>
export PRIVATE_KEY=<your-private-key>
export ADMIN_ADDRESS=<admin-address>
npm run deploy:testnet
```

## Security

The contracts implement various security measures:

- Reentrancy guards on all sensitive functions
- Pausable functionality for emergency situations
- Role-based access control for administrative functions
- Input validation with proper error messages
- Events for all important state changes

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Contact

For any questions or feedback, please contact the CrossFi team at dev@crossfi.org.
