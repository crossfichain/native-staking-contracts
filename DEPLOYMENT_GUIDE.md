# Native Staking Contracts - Deployment Guide

This document outlines the process for deploying the split Native Staking contract architecture to production, including testing procedures, verification steps, and post-deployment checks.

## Prerequisites

- Access to deployment wallet with sufficient funds
- Admin address for contract ownership
- Operator address for management functions
- Emergency address for circuit-breaker functions
- DIA Oracle address for price feeds
- WXFI token address (if deploying to production)

## Pre-Deployment Checklist

1. **Source Code Verification**
   - Ensure all contracts compile without errors or warnings
   - Verify all tests are passing (`forge test -vvv`)
   - Check contract sizes (`forge build --sizes`)
   - Verify that all contracts are within the Ethereum size limit (24,576 bytes)

2. **Security Checks**
   - Run static analysis tools (Slither, Mythril)
   - Verify access controls are properly implemented
   - Check for potential reentrancy vulnerabilities
   - Validate initialization functions and proxy patterns

3. **Split Architecture Verification**
   - Ensure `NativeStakingManagerLib` library contains correct enums and calculation functions
   - Verify `BaseNativeStakingManager` correctly implements the interface
   - Validate `SplitNativeStakingManager` implements all required functionality
   - Test inheritance chain and overrides

## Deployment Process

### 1. Library Deployment

Deploy the `NativeStakingManagerLib` library first:

```sh
forge script script/deploy/DeploySplitContracts.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

### 2. Implementation Contracts

Deploy the implementation contracts:

1. `UnifiedOracle` implementation
2. `NativeStaking` (APR) implementation
3. `NativeStakingVault` (APY) implementation
4. `SplitNativeStakingManager` implementation

### 3. Proxy Admin Deployment

Deploy the `ProxyAdmin` contract that will manage all proxies.

### 4. Proxy Deployments

Deploy the proxies in the following order:

1. Oracle proxy with initialization
2. APR Staking proxy with initialization
3. APY Staking proxy with initialization
4. Staking Manager proxy with initialization

### 5. System Configuration

Configure the system by setting up roles:

1. Grant admin roles to the admin address
2. Grant operator roles to the operator address
3. Grant emergency roles to the emergency address
4. Configure cross-contract permissions

## Verification Steps

### 1. Size Verification

Verify all contract sizes are within limits:

```sh
forge run test_only/ContractSizeTest.sol
```

### 2. Interface Implementation Verification

Verify all interfaces are correctly implemented:

```sh
forge test test/UpgradeVerification.t.sol -vvv
```

### 3. Proxy Configuration Verification

Verify all proxies are pointing to the correct implementation:

```sh
cast call <PROXY_ADMIN> "getProxyImplementation(address)" <PROXY_ADDRESS>
```

### 4. Role Verification

Verify all roles are correctly assigned:

```sh
cast call <CONTRACT_ADDRESS> "hasRole(bytes32,address)" <ROLE_HASH> <ADDRESS>
```

## Post-Deployment Checks

### 1. Functionality Verification

1. Test staking with test tokens
2. Test unstaking with test tokens
3. Test rewards claiming
4. Test role operations
5. Test emergency controls

### 2. Contract Verification

Verify contract source code on Etherscan/block explorer:

```sh
forge verify-contract --chain <CHAIN_ID> --watch <ADDRESS> <CONTRACT_NAME>
```

### 3. Upgrade Process Verification

Test the upgrade mechanism with a test implementation:

```sh
forge test test/UpgradeVerification.t.sol:testUpgradeImplementation -vvv
```

## Emergency Procedures

### 1. Circuit Breaker

In case of emergency, the system can be paused:

```sh
cast send <STAKING_MANAGER> "pause()" --private-key <EMERGENCY_KEY>
```

### 2. Freezing Unstaking

If necessary, unstaking can be frozen:

```sh
cast send <STAKING_MANAGER> "freezeUnstaking(uint256)" <DURATION> --private-key <EMERGENCY_KEY>
```

### 3. Emergency Upgrade

If a critical vulnerability is discovered:

1. Deploy a new implementation
2. Upgrade the proxy to the new implementation

```sh
cast send <PROXY_ADMIN> "upgrade(address,address)" <PROXY> <NEW_IMPL> --private-key <ADMIN_KEY>
```

## Monitoring

### 1. Event Monitoring

Monitor key events:
- Staking events
- Unstaking events
- Rewards claiming events
- Role changes
- Upgrades

### 2. Size Monitoring

Regularly check contract sizes after upgrades to ensure they remain under the limit.

## Conclusion

This split architecture provides a robust solution to the contract size limitation while maintaining all functionality. By following this deployment guide, you can ensure that the system is deployed correctly and functions as expected.

Remember to always test thoroughly on testnets before deploying to production, and to have emergency procedures ready in case of issues. 