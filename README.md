# Native Staking Contracts

Smart contracts for staking native XFI tokens to CrossFi validators with Oracle integration for MPX conversion.

## Overview

The Native Staking system allows users to stake their native XFI tokens to validators in the CrossFi network. The system includes:

- **Two-step unstaking** - Initiated by users, completed by operators
- **Reward claiming** - Two-step process with backend integration
- **Validator management** - Add, update status, and migrate between validators
- **Emergency withdrawal** - Safety feature for urgent situations
- **Oracle integration** - XFI/MPX price conversion

## Architecture

![System Architecture](./docs/diagrams/system-architecture.png)

The system consists of three main components:
- **Core contracts**: NativeStaking for staking operations
- **Periphery contracts**: UnifiedOracle for price feeds
- **Libraries**: Utilities for validation and price conversion

## Documentation

Detailed documentation is available in the `/docs` directory:

- [System Architecture](./docs/architecture/ARCHITECTURE.md) - Component overview and interactions
- [Contract Flows](./docs/architecture/FLOWS.md) - Detailed operation flows with diagrams
- [Deployment Guide](./docs/guides/DEPLOYMENT.md) - Step-by-step deployment instructions
- [Oracle Integration](./docs/architecture/ORACLE.md) - Price feed and conversion details
- [Role-Based Access](./docs/guides/ROLES.md) - Role configuration and management

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 16+

### Setup

1. Clone the repository
2. Copy `.env.example` to `.env` and configure your environment
3. Install dependencies:

```bash
forge install
```

### Testing

```bash
forge test
```

### Deployment

For development deployment:

```bash
forge script script/DeployNativeStakingDev.s.sol:DeployNativeStakingDev --broadcast --rpc-url $RPC_URL -vvv
```

For production deployment, see the [Deployment Guide](./docs/guides/DEPLOYMENT.md).

## Security

This code is pending audit and is not recommended for production use until a thorough security review has been completed.

## License

MIT 