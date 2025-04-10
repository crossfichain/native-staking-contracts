# Native Staking System Architecture

This document provides a comprehensive overview of the Native Staking system architecture, explaining its components, interactions, and design decisions.

## System Components

The Native Staking system consists of three main components:

[![System Architecture](https://mermaid.ink/img/pako:eNp9ksFugzAMhl_F8rGgLV27sYSoYod1p52q9tJLCG6LlMRIHIqG-u4jELbSOZ3i75fj32AcJCpHMIS5_KazTKFAw8N-z5P3l5cDi8-2wB2XR9TrZ7oBIchCn0AHvnVYosBVVZVF_nwV5yuICdptzAxFUehr1UZOYt81nKNBstP0VMj64veMH-YWvUTpPtvs_2dOhyhqMul5fsdPIlEoQvlEwBgUTg3h9KLUMKotyP90Uh5XyPXBYANdG3E6QZoqPIPoW38jxDUCGcPCcZTTG19mjSqlr5EB6v4KXrbnJRU9TEcswk6q7YPVuEo5P9CwQwOCQn7vfxKUYN5RdC-JC7YQh1L7-UPoDNVfD5NggEmyR1WiJQxGDHxZ34YKVOdTUXMOg81Lnr2ZRtl5g-WuLArJFZTDJ0Uadjw?type=png)](https://mermaid.live/edit#pako:eNp9ksFugzAMhl_F8rGgLV27sYSoYod1p52q9tJLCG6LlMRIHIqG-u4jELbSOZ3i75fj32AcJCpHMIS5_KazTKFAw8N-z5P3l5cDi8-2wB2XR9TrZ7oBIchCn0AHvnVYosBVVZVF_nwV5yuICdptzAxFUehr1UZOYt81nKNBstP0VMj64veMH-YWvUTpPtvs_2dOhyhqMul5fsdPIlEoQvlEwBgUTg3h9KLUMKotyP90Uh5XyPXBYANdG3E6QZoqPIPoW38jxDUCGcPCcZTTG19mjSqlr5EB6v4KXrbnJRU9TEcswk6q7YPVuEo5P9CwQwOCQn7vfxKUYN5RdC-JC7YQh1L7-UPoDNVfD5NggEmyR1WiJQxGDHxZ34YKVOdTUXMOg81Lnr2ZRtl5g-WuLArJFZTDJ0Uadjw)

### 1. Core Contracts

The core contracts manage all staking operations:

- **NativeStaking.sol**: The primary contract handling staking, unstaking, reward claiming, and validator management
  - Implements role-based access control (Admin, Manager, Operator)
  - Manages stake data and validator registry
  - Implements two-step processes for operations
  - Handles time restrictions for operations

### 2. Periphery Contracts

Auxiliary contracts that support the main staking functionality:

- **UnifiedOracle.sol**: Provides price feed data and token conversion
  - Integrates with DIA Oracle for XFI/USD price data
  - Maintains MPX price information
  - Handles token conversion calculations

### 3. Libraries

Utility libraries that provide reusable functionality:

- **StakingUtils.sol**: Utility functions for staking operations
  - Validator ID and address validation
  - Time-based operation validation
  - String manipulation and normalization

- **ValidatorAddressUtils.sol**: Specialized functions for validator address handling
  - Address format validation and normalization
  - Bech32 address part extraction

- **PriceConverter.sol**: Utilities for token price conversion
  - XFI to MPX conversion based on oracle data
  - XFI to USD value calculation

### 4. Interfaces

Contract interfaces defining the interaction surfaces:

- **INativeStaking.sol**: Interface for the NativeStaking contract
  - Defines all external functions, events, structs, and errors
  - Serves as documentation for integration

- **IOracle.sol**: Interface for Oracle price feed functionality
  - Defines price retrieval and conversion functions

- **IDIAOracle.sol**: Interface for interaction with external DIA Oracle
  - Defines functions to get XFI/USD price data

## Contract Relationships

[![Contract Relationships](https://mermaid.ink/img/pako:eNqFk91qwzAMhV_F-KrCsi7ZdWLSOFvXqzYd7aWNbpJSMie2c5PQkHffjG3S_YyL5HzWhyxLToAixQAdeDM9SDXUJEGifV-HzyQRg4wHVbXVPSl3HuMApzXKUZEEU_DNHVS1KOr8lErXRJwjPFyuO7yiFi4_JWIz6qCWqJCsdT0a2byZFvG62dUbSJLjMWr-7yiVQoLN4DX0Nj1vqSo0SttwgEH6s_NztVrZqqc6D_eF7R7hynuaJ9yzYT-aqBTaHnL5Y2IKF0jByqQHRZPiVgHxU6fMt2Xz4ZKbmL-G3B_MHNEuEHSxfImQtDMmSZdW3NFmSFKuJ0ZCUV3RL1lTdCo1pfQNCnBuq2Ixzz2ltQYjSuNbgzMzF1DXYHdMgn78z18BJPRekB_JMCW9k3a9gACmwcf6JMmA5W8Z3eDtSs1p-4cT52Pm9LSipmqJGD-SrlVJ?type=png)](https://mermaid.live/edit#pako:eNqFk91qwzAMhV_F-KrCsi7ZdWLSOFvXqzYd7aWNbpJSMie2c5PQkHffjG3S_YyL5HzWhyxLToAixQAdeDM9SDXUJEGifV-HzyQRg4wHVbXVPSl3HuMApzXKUZEEU_DNHVS1KOr8lErXRJwjPFyuO7yiFi4_JWIz6qCWqJCsdT0a2byZFvG62dUbSJLjMWr-7yiVQoLN4DX0Nj1vqSo0SttwgEH6s_NztVrZqqc6D_eF7R7hynuaJ9yzYT-aqBTaHnL5Y2IKF0jByqQHRZPiVgHxU6fMt2Xz4ZKbmL-G3B_MHNEuEHSxfImQtDMmSZdW3NFmSFKuJ0ZCUV3RL1lTdCo1pfQNCnBuq2Ixzz2ltQYjSuNbgzMzF1DXYHdMgn78z18BJPRekB_JMCW9k3a9gACmwcf6JMmA5W8Z3eDtSs1p-4cT52Pm9LSipmqJGD-SrlVJ)

The diagram above shows how contracts interact with each other:

1. The **NativeStaking** contract is the central component that users interact with directly
2. It uses **UnifiedOracle** for price conversions between XFI and MPX
3. The Oracle connects to **DIA Oracle** for external price data
4. **Libraries** are used by NativeStaking for utility functions
5. All contracts implement their respective **interfaces**

## Role-Based Access Control

The system implements a tiered access control model:

1. **Admin** (DEFAULT_ADMIN_ROLE)
   - Full control over the system
   - Can grant and revoke all roles
   - Typically controlled by a multi-sig wallet for security

2. **Manager** (MANAGER_ROLE)
   - Manages validator registry
   - Configures system parameters
   - Controls pause/unpause functionality
   - Manages validator migrations

3. **Operator** (OPERATOR_ROLE)
   - Technical role for backend operations
   - Completes unstaking processes
   - Processes reward claims
   - Handles emergency withdrawals

4. **User** (no special role)
   - Can stake XFI tokens
   - Can initiate unstaking
   - Can request reward claims
   - Can migrate stakes when allowed

## Data Model

### Key Storage Structures

1. **Validator Registry**
   ```solidity
   mapping(string => Validator) private _validators;
   string[] private _validatorIds;
   ```

2. **User Stakes**
   ```solidity
   mapping(address user => mapping(string validatorId => UserStake)) private _userStakes;
   mapping(address user => string[] validators) private _userValidators;
   mapping(address user => uint256 totalStaked) private _userTotalStaked;
   ```

3. **Emergency Withdrawal Tracking**
   ```solidity
   mapping(address user => bool emergencyWithdrawalRequested) private _emergencyWithdrawalRequested;
   ```

### Core Data Structures

1. **Validator** - Represents a validator in the system
   ```solidity
   struct Validator {
       string id;
       ValidatorStatus status;
       uint256 totalStaked;
       uint256 uniqueStakers;
   }
   ```

2. **UserStake** - Represents a user's stake to a specific validator
   ```solidity
   struct UserStake {
       uint256 amount;
       uint256 mpxAmount;
       uint256 stakedAt;
       uint256 lastClaimedAt;
       bool inUnstakeProcess;
       uint256 lastUnstakedAt;
       uint256 unstakeAmount;
   }
   ```

3. **ValidatorStatus** - Enum defining possible validator states
   ```solidity
   enum ValidatorStatus {
       Disabled,
       Enabled,
       Deprecated
   }
   ```

## Upgradeability

The system uses the Transparent Proxy pattern for upgradeability:

1. **Implementation Contracts**
   - Core contract logic that can be upgraded

2. **Proxy Contracts**
   - Maintain contract state and delegate calls to implementations
   - Allow for upgrading logic without losing state

3. **Proxy Admin**
   - Controls the upgrade process
   - Manages proxy configurations

This design ensures that the system can evolve without disrupting users or requiring migration of assets.

## Security Considerations

1. **Reentrancy Protection**
   - Use of ReentrancyGuard for all external functions that transfer value
   - Checks-Effects-Interactions pattern implementation

2. **Access Control Enforcement**
   - Role-based permissions for all administrative functions
   - Granular access control with principle of least privilege

3. **Timelock Constraints**
   - Minimum time intervals between operations
   - Configurable by administrators for risk management

4. **Pausability**
   - Emergency pause functionality for staking operations
   - Separate pause controls for different operation types

For more detailed information on specific components, see the dedicated documentation pages. 