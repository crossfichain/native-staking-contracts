# Role-Based Access Control

This document details the Role-Based Access Control (RBAC) system implemented in the Native Staking contracts, which ensures proper access management and operational security.

## Overview

The Native Staking system implements a comprehensive role-based access control system using OpenZeppelin's AccessControl contract. This approach ensures that only authorized addresses can perform specific administrative and operational functions, reducing security risks and creating a clear separation of responsibilities.

[![RBAC Structure](https://mermaid.ink/img/pako:eNqFksFOwzAMhl_FymmT2gHXXSYGByTEA-wCHLrEW4varNBk0jTtdXHnhmDHOdIhPkf-_f-O7FMUPJeYeFTI_EmO-aWxRtcGkz8nMn37-PDWyuHdx4Suf2Aymb-bJiqMDTRYUQVJ_wYeV5P5C3j_YQQsRblWtbTTs_jiNLr95wy-tK5pNa8OmyH72_pgnbSs7DlsWONTJHLqNk_OfhxJ57yq5OiGYmDY-XZwRBfKZb5sXkJd0LLsOBTKVsyDIpADpN0fF-LFoDaWvEHLUvGlUk1PsLWQG1KSjYiL12V-hshW5qTKSuWh7XZppWnTtGz7CdU2gmmT1q49mwVnWj-DcXIhC6LRGdL1JBGHKEsD5UdQoQnf2FLjKlgBnYc1LvGwRH-nwsOSQ81bZCpk1uGZl5iMqCj8K4lv3n63s3Hp3BKxdndOLDavMI7tOPzdcnpSTT1VPsrG6bIYKEpJVN95ZZQZnKjP0DuKhsb5esPo3JBvzPh64Hvqy9MqL5F46YFe8IlJKo92aqLGLpL_xrVbo4vnDQSw7_IH?type=png)](https://mermaid.live/edit#pako:eNqFksFOwzAMhl_FymmT2gHXXSYGByTEA-wCHLrEW4varNBk0jTtdXHnhmDHOdIhPkf-_f-O7FMUPJeYeFTI_EmO-aWxRtcGkz8nMn37-PDWyuHdx4Suf2Aymb-bJiqMDTRYUQVJ_wYeV5P5C3j_YQQsRblWtbTTs_jiNLr95wy-tK5pNa8OmyH72_pgnbSs7DlsWONTJHLqNk_OfhxJ57yq5OiGYmDY-XZwRBfKZb5sXkJd0LLsOBTKVsyDIpADpN0fF-LFoDaWvEHLUvGlUk1PsLWQG1KSjYiL12V-hshW5qTKSuWh7XZppWnTtGz7CdU2gmmT1q49mwVnWj-DcXIhC6LRGdL1JBGHKEsD5UdQoQnf2FLjKlgBnYc1LvGwRH-nwsOSQ81bZCpk1uGZl5iMqCj8K4lv3n63s3Hp3BKxdndOLDavMI7tOPzdcnpSTT1VPsrG6bIYKEpJVN95ZZQZnKjP0DuKhsb5esPo3JBvzPh64Hvqy9MqL5F46YFe8IlJKo92aqLGLpL_xrVbo4vnDQSw7_IH)

## Role Definitions

The Native Staking system defines the following roles:

### 1. DEFAULT_ADMIN_ROLE

```solidity
bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
```

The DEFAULT_ADMIN_ROLE is the highest administrative role in the system, with the authority to:
- Grant and revoke all roles, including other admin roles
- Complete emergency protocol shutdown if necessary
- Execute critical security functions

### 2. MANAGER_ROLE

```solidity
bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
```

The MANAGER_ROLE is responsible for overall protocol management:
- Register validators and update their details
- Set and update protocol parameters
- Configure global protocol settings
- Adjust time restrictions for operations
- Pause/unpause specific contract functions

### 3. OPERATOR_ROLE

```solidity
bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
```

The OPERATOR_ROLE handles day-to-day validator operations:
- Complete unstaking operations initiated by users
- Process validator reward distribution
- Flag validator misbehavior
- Update validator status information
- Execute time-sensitive operational functions

### 4. Regular Users

Regular users don't have a specific role but interact with the protocol through public functions:
- Stake XFI tokens to validators
- Initiate unstaking processes
- Claim rewards
- Request emergency withdrawals
- Query their stake information

## Role Implementation

The role-based access control is implemented using OpenZeppelin's AccessControl pattern:

```solidity
// NativeStaking.sol
contract NativeStaking is 
    INativeStaking,
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    function initialize(address admin, address manager, address operator) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(MANAGER_ROLE, manager);
        _setupRole(OPERATOR_ROLE, operator);
        
        // Grant the admin role permission to grant other roles
        _setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, DEFAULT_ADMIN_ROLE);
    }
    
    // Role-restricted functions example
    function registerValidator(
        address validatorAddress,
        string memory name,
        uint256 commissionRate
    ) external override onlyRole(MANAGER_ROLE) {
        // Implementation
    }
    
    function completeUnstake(
        address user,
        uint256 validatorId,
        uint256 unstakeAmount,
        uint256 rewardAmount
    ) external override onlyRole(OPERATOR_ROLE) nonReentrant {
        // Implementation
    }
    
    // Function for administrative pausing
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    // UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        // Additional validation if needed
    }
}
```

## Role Assignments

Roles are assigned during contract initialization and can be modified by the DEFAULT_ADMIN_ROLE:

```solidity
// From DeployNativeStakingDev.s.sol
function run() public {
    // Prepare addresses
    address adminAddress = vm.addr(vm.envUint("ADMIN_PRIVATE_KEY"));
    address managerAddress = vm.addr(vm.envUint("MANAGER_PRIVATE_KEY"));
    address operatorAddress = vm.addr(vm.envUint("OPERATOR_PRIVATE_KEY"));
    
    // Deploy and initialize
    nativeStaking.initialize(adminAddress, managerAddress, operatorAddress);
}
```

## Role Management

Roles can be granted or revoked using the standard OpenZeppelin AccessControl functions:

```solidity
// Grant a role
function grantRole(bytes32 role, address account) external;

// Revoke a role
function revokeRole(bytes32 role, address account) external;

// Renounce a role (self-removal)
function renounceRole(bytes32 role, address account) external;
```

For example, to add a new operator:

```solidity
// Can only be called by DEFAULT_ADMIN_ROLE
nativeStaking.grantRole(OPERATOR_ROLE, newOperatorAddress);
```

## Role Modifiers

The RBAC system is enforced using OpenZeppelin's `onlyRole` modifier:

```solidity
modifier onlyRole(bytes32 role) {
    require(hasRole(role, _msgSender()), "AccessControl: account lacks role");
    _;
}
```

Each restricted function uses this modifier to ensure that only authorized addresses can execute it:

```solidity
function updateValidatorStatus(uint256 validatorId, ValidatorStatus status) 
    external 
    override 
    onlyRole(OPERATOR_ROLE) 
{
    // Implementation
}
```

## Security Considerations

### Role Separation

The system enforces strict separation of duties:
- **Admin**: Focuses on critical protocol governance and security
- **Manager**: Handles validator registration and parameter configuration
- **Operator**: Manages day-to-day operations and user transactions

This separation ensures that compromise of a single role cannot fully compromise the protocol.

### Multi-Signature Wallets

For production deployments, roles should be assigned to multi-signature wallets:
- DEFAULT_ADMIN_ROLE: 3/5 multi-sig wallet
- MANAGER_ROLE: 2/3 multi-sig wallet
- OPERATOR_ROLE: Can be a hot wallet with careful key management

### Role Rotation

The system supports role rotation for security:
1. Admin can grant a new address the required role
2. Verify the new address has proper access
3. Revoke the role from the old address

### Emergency Procedures

In case of compromise:
1. The admin can revoke compromised roles immediately
2. The admin can pause the contract to prevent further actions
3. New role assignments can be made to trusted addresses

## Events and Monitoring

The OpenZeppelin AccessControl contract emits standard events for role changes:

```solidity
event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
```

These events should be monitored for unauthorized role changes.

## Best Practices

1. **Minimal Privilege**: Assign the minimum necessary privileges to each role
2. **Regular Audits**: Conduct regular audits of role assignments
3. **Secure Key Management**: Use secure key management for all role addresses
4. **Role Rotation**: Periodically rotate role addresses as a security measure
5. **Multi-Sig Wallets**: Use multi-sig wallets for sensitive roles
6. **Emergency Plans**: Maintain clear procedures for role revocation in emergencies

For more details on the RBAC implementation, refer to the OpenZeppelin AccessControl documentation and the contract source code in the repository. 