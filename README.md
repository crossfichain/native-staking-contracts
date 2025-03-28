# CrossFi Native Staking Contracts

This repository contains the smart contracts for CrossFi's Native Staking system, which allows users to stake XFI tokens through two different models:

1. **APR Model (Direct Staking)** - Users stake XFI, specify validators, and earn rewards based on a simple interest model
2. **APY Model (Compounding Vault)** - Users stake XFI in a vault (ERC-4626 compliant) and earn compounding rewards

## Architecture

The system is built with a modular architecture that consists of:

### Core Contracts

- **NativeStakingManager**: Central router for all staking operations, handling both native XFI and wrapped XFI (WXFI)
- **APRStaking**: Implements the APR staking model with direct validator delegation
- **NativeStakingVault**: Implements the APY staking model following the ERC-4626 standard

### Periphery Contracts

- **UnifiedOracle**: Provides price data and validator information from the Cosmos chain
- **WXFI**: Wrapped XFI implementation that allows native XFI to be used as an ERC20 token

### Deployment

- **DeploymentCoordinator**: Helper contract for deploying the entire system with proper proxy setup

## Technical Features

- **Upgradeable Contracts**: All core contracts use the TransparentUpgradeableProxy pattern
- **Role-Based Access Control**: Granular permissions system using OpenZeppelin's AccessControl
- **Security Measures**: Reentrancy protection, pause functionality, and other security best practices
- **ERC-4626 Compliance**: The vault follows the standard for tokenized vaults
- **Native Token Support**: Users can stake and unstake using native XFI or wrapped XFI (WXFI)

## Recent Improvements

We've recently made several improvements to the contracts:

1. **Contract Stability**: Fixed inheritance linearization in the APRStaking contract
2. **Native Token Operations**: Improved error handling for native XFI operations
3. **MockWXFI Contract**: Enhanced ETH balance checking and error handling
4. **Test Coverage**: Updated tests to verify native token operations
5. **Request ID Handling**: Improved mapping between different request ID formats

See the `IMPLEMENTED_FIXES.md` file for detailed information about recent fixes.

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

To run all tests:

```bash
forge test
```

To run only passing tests:

```bash
test/e2e/run_passing_tests.sh
```

This script includes the following test suites:
- Validator Staking Tests
- Vault Staking Tests
- Edge Cases Tests
- Native Token Tests
- Admin Operations Tests

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

## Known Issues

Some advanced features still need implementation:
- Full bytes request ID support across all contracts
- Comprehensive test coverage for all edge cases
- Additional safeguards for large-scale staking operations

See the `PENDING_FIXES.md` file for a detailed roadmap of planned improvements.

## Security

The contracts implement various security measures:

- Reentrancy guards on all sensitive functions
- Pausable functionality for emergency situations
- Role-based access control for administrative functions
- Input validation with proper error messages
- Events for all important state changes
- Error handling for native token operations

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Contact

For any questions or feedback, please contact the CrossFi team at dev@crossfi.org.
