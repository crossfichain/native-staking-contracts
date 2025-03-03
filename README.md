# CrossFi Native Staking Contracts

A simplified staking system that allows users to stake XFI tokens with validators. This is the optimized, refactored version of the original contracts.

## Architecture

The architecture has been simplified to make the system easier to maintain, upgrade, and understand:

### Core Contracts

1. **StakingProxy** (`src/StakingProxy.sol`)
   - User-facing contract that acts as the main entry point to the staking system
   - Proxies user calls to the StakingCore contract
   - Provides a simple and stable API for users and frontends

2. **StakingCore** (`src/StakingCore.sol`)
   - Core logic contract that manages positions, validators, and staking/unstaking functionality
   - Handles reward calculations and distribution
   - Maintains state for user positions and validator information

3. **Oracle** (`src/Oracle.sol`)
   - Handles price data and reward rate information
   - Integrates with DIA Oracle for external price feeds
   - Manages reward periods and rates

### Interfaces

- **IStakingCore** (`src/interfaces/IStakingCore.sol`) - Interface for the core staking functionality
- **IOracle** (`src/interfaces/IOracle.sol`) - Interface for the oracle functionality
- **IDIAOracle** (`src/interfaces/IDIAOracle.sol`) - Interface for interacting with the DIA Oracle

## System Design

1. **User Flow**
   - Users interact with the StakingProxy contract
   - StakingProxy delegates calls to StakingCore
   - All staking positions are tracked in StakingCore

2. **Validator Management**
   - Validators are registered and managed by operators
   - Users can select from active validators to stake with
   - Rewards are distributed per validator

3. **Rewards Mechanism**
   - Rewards are accumulated in validator-specific pools
   - Users can claim rewards from all their validator positions
   - Rewards can be reinvested automatically

4. **Oracle Integration**
   - Price data is retrieved from DIA Oracle
   - Fallback mechanisms ensure system reliability
   - APR data is maintained for transparency

## Key System Features

- **Simplified Architecture**: Clean separation of concerns between user interface, core logic, and oracle
- **Position Management**: Support for multiple validator positions per user
- **Validator Selection**: Users can choose specific validators to stake with
- **Flexible Rewards**: Claim or reinvest rewards at any time
- **Upgrade Path**: Contracts can be upgraded by changing proxy targets
- **Security Features**: Access control, reentrancy protection, and emergency pausing

## Development

### Prerequisites

- Node.js v16+
- Hardhat
- Solidity 0.8.20

### Setup

```bash
npm install
```

### Testing

```bash
npx hardhat test
```

### Deployment

```bash
npx hardhat run scripts/deploy.js --network <network>
```
