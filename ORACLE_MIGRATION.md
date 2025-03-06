# Oracle Migration Guide

## Overview

This document outlines the migration path from the current CrossFiOracle and UnifiedOracle implementations to the new consolidated production-ready ProductionOracle. The ProductionOracle combines the best features of both implementations and provides robust integration with the DIA Oracle for price data.

## Key Features of ProductionOracle

1. **DIA Oracle Integration**: Properly handles the conversion of 8 decimal places from DIA to 18 decimals used internally.
2. **Fallback Mechanism**: If the DIA Oracle price is unavailable or outdated, uses a fallback price stored in the Oracle.
3. **Price Freshness Check**: Ensures that prices are recent by checking the timestamp of the price update.
4. **Role-Based Access Control**: Clear separation of roles for Oracle updaters, pausers, and admin functions.
5. **Pause Functionality**: Ability to pause sensitive functions in case of emergency.
6. **Batch Operations**: Efficiency improvements with batch setting of user rewards.
7. **Better Documentation**: Comprehensive NatSpec comments for all functions.

## Migration Steps

### 1. Deploy the New Oracle

```solidity
// Deploy DIA Oracle (or get the address of the existing one)
address diaOracleAddress = 0x...;

// Deploy the ProductionOracle implementation
ProductionOracle oracleImpl = new ProductionOracle();

// Deploy the ProxyAdmin
ProxyAdmin proxyAdmin = new ProxyAdmin();

// Initialize data
bytes memory oracleInitData = abi.encodeWithSelector(
    ProductionOracle.initialize.selector,
    diaOracleAddress
);

// Deploy the Proxy
TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
    address(oracleImpl),
    address(proxyAdmin),
    oracleInitData
);

// Get a reference to the Oracle
ProductionOracle oracle = ProductionOracle(address(oracleProxy));
```

### 2. Set Up Initial Values

```solidity
// Set initial values
oracle.setCurrentAPR(10); // 10%
oracle.setCurrentAPY(8);  // 8%
oracle.setUnbondingPeriod(21 days);
oracle.setTotalStakedXFI(/* current total staked */);

// Set fallback price for XFI
oracle.setPrice("XFI", 1 ether); // $1 with 18 decimals
```

### 3. Grant Roles

```solidity
// Grant roles
oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), /* address with update rights */);
oracle.grantRole(oracle.PAUSER_ROLE(), /* address with pause rights */);
oracle.grantRole(oracle.UPGRADER_ROLE(), /* address with upgrade rights */);
oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), /* admin address */);
```

### 4. Migrate User Data

For each user with claimable rewards in the old Oracle:

```solidity
// Batch set user claimable rewards
address[] memory users = /* array of user addresses */;
uint256[] memory amounts = /* array of claimable reward amounts */;
oracle.batchSetUserClaimableRewards(users, amounts);
```

### 5. Update References in Other Contracts

Update the Oracle address in all contracts that reference it:

```solidity
// Update NativeStaking
nativeStaking.setOracle(address(oracle));

// Update NativeStakingVault
nativeStakingVault.setOracle(address(oracle));

// Update NativeStakingManager
nativeStakingManager.setOracleAddress(address(oracle));
```

## Testing the Migration

1. **Verify Price Access**: Ensure that all contracts can correctly access XFI prices.
2. **Verify Rewards**: Test that user rewards are migrated correctly.
3. **Verify Staking Functions**: Test staking, unstaking, and reward claiming with the new Oracle.
4. **Verify Decimal Handling**: Ensure that the decimal conversion from DIA (8 decimals) to internal (18 decimals) works correctly.
5. **Verify Roles**: Ensure that the roles are set up correctly and that only authorized addresses can perform sensitive operations.

## FAQ

**Q: Will there be any downtime during the migration?**
A: Yes, contracts that depend on the Oracle will need to be paused during the migration to prevent inconsistent state.

**Q: What happens to existing user rewards?**
A: All user rewards will be migrated to the new Oracle. Users should not lose any accrued rewards.

**Q: How do we handle price freshness?**
A: The new Oracle has a built-in freshness check. If the DIA Oracle price is older than 1 hour, it will fall back to the manually set price.

**Q: How do we convert between DIA's 8 decimals and our 18 decimals?**
A: The conversion is handled automatically in the `getXFIPrice()` function: `price = uint256(diaPrice) * 1e18 / 1e8`.

## Conclusion

The new ProductionOracle is a significant improvement over the previous implementations, with better integration, more robust fallback mechanisms, and clearer role separation. This migration will ensure that the Native Staking system has a reliable source of price data and can accurately calculate and distribute rewards to users. 