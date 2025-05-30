# ������������ �� ��������� NativeStaking

## ����������
1. [����� ���������](#�����-���������)
2. [���� � ����������](#����-�-����������)
3. [�������� ������](#��������-������)
4. [�������������� � ��������](#��������������-�-��������)
5. [����������� XFI/MPX](#�����������-xfimpx)
6. [�����������](#�����������)
7. [����������� �� �������������](#�����������-��-�������������)

## ����� ���������

`NativeStaking` - ��� �����-�������� ��� ��������� �������� ������� XFI � ���������� ���� CrossFi. �������� ���������� ��� �������������� ������������� ����������� ������������ ���� ������ XFI ����������� � �������� �������������� �� ������� � ������� ���������.

�������� �����������:
- **�������� XFI**: ������������ ����� �������� ���� ������ XFI ������ ��������� ���������� �� ������ ���������
- **����������� ����������**: ������� ������� ������� ������� �� ��������� (�������������) � ���������� (����������)
- **��������� ������**: ������������ ����� ����������� � �������� ���� ������� ����� ����������� �������
- **���������� ����� �������**: � ������������ ��������� ������������ ����� ��������� ����� ���� �������
- **�������� �������**: ����������� �������� ������� ����� ������������ ��� �������������
- **������������� ���������**: ��������� ������-������� ��� ������� ���������� ����������������

�������� ������������� � �������������� �������� ������������ ������, ��� ��������� ������� ��������� � ������ ��� ������ ��������� � ������. �� �������� ������� ��� ���������� ������������, ��������� ��������� ����������� � ��������� �������� ���������.

## ���� � ����������

������� ����� � ���������� � ��������� �������� �� OpenZeppelin AccessControl, ��� ������������ ������ � ���������� ������ ����������. � ��������� ���������� ��������� ����:

| ���� | ��������� | �������� |
|------|-----------|----------|
| ������������� | DEFAULT_ADMIN_ROLE | ���������� ����� ������ � ������ ������ � ���������. ����� ��������� � �������� ���� ������ �������������. |
| �������� | MANAGER_ROLE | ���������� ����������� ���������, ������� ����������/���������� �����������, ��������� ��������� ����������, ������������ ��������. |
| �������� | OPERATOR_ROLE | ����������� ���� ��� �������, ���������� �� ���������� ��������� ����������� � ������� ������ �������������. |

����� ���������� ����� ������������ ������� ���������� ���������� � ��������� ��������������� ���������� ����������.

### �������� ������� ��� ��������������

������������� ����� ��������� ������ � �������:

```solidity
// src/core/NativeStaking.sol
// �������������� ���� ���������� ������
function grantRole(bytes32 role, address account) external;

// ����� ���� � ���������� ������
function revokeRole(bytes32 role, address account) external;
```

### �������� ������� ��� ���������

�������� �������� �� ��������� ���������� ���������:

```solidity
// src/core/NativeStaking.sol
// ���������� ������ ���������� � �������
function addValidator(string calldata validatorId, bool isEnabled) external;

// ���������� �������� ���������� (�������, ��������, �������)
function updateValidatorStatus(string calldata validatorId, ValidatorStatus status) external;

// ��������� ����������� ��������� ���������� ��� ��������
function setMinStakeInterval(uint256 interval) external;
function setMinUnstakeInterval(uint256 interval) external;
function setMinClaimInterval(uint256 interval) external;

// ������������ � ������������� ��������
function pauseStaking() external;
function unpauseStaking() external;
```

### �������� ������� ��� ���������

�������� ��������� ����������� ����� ��������:

```solidity
// src/core/NativeStaking.sol
// ���������� �������� �����������
function completeUnstake(address staker, string calldata validatorId, uint256 amount) external;

// ������� ������ ������������
function completeRewardClaim(
    address staker, 
    string calldata validatorId, 
    uint256 amount,
    bool isInitiatedDueUnstake
) external payable;

// ��������������� ������� ����������� � ������� ������
function processRewardAndUnstake(
    address staker, 
    string calldata validatorId, 
    uint256 unstakeAmount,
    uint256 rewardAmount
) external;
```

### �������� ������� ��� �������������

������������ ����� ��������� ��������� �������� ��������:

```solidity
// src/core/NativeStaking.sol
// �������� ������� XFI � ���������� ����������
function stake(string calldata validatorId) external payable;

// ������ �� ����� ������� (������ ���� �����������)
function initiateUnstake(string calldata validatorId, uint256 amount) external;

// ������ �� ��������� ������
function initiateRewardClaim(string calldata validatorId) external;

// ������ �� ���������� ����� ���� �������
function initiateEmergencyWithdrawal() external;
```

## �������� ������

### ������� ���������

�������� - ��� �������� ��������, ����������� ������������� ������������ ���� XFI �����������. ������� ���������� � ���� ����:

```mermaid
sequenceDiagram
    participant ������������
    participant ��������
    participant Oracle
    
    ������������->>��������: stake(validatorId) {value: ���������� XFI}
    ��������->>��������: �������� ���������� � ���������� ����������
    ��������->>��������: �������� ��������� ����������� � ������� ���������� ������
    ��������->>Oracle: ����������� XFI � MPX ��� ����������� � �������
    ��������->>��������: ���������� ������ ������ ������������ � ���������� ����������
    ��������-->>������������: ���� ������� Staked(user, validatorId, xfiAmount, mpxAmount)
```

**������ ������ �������� ���������:**
- ��� ��������� ������ � ���� �� ����������, ����� ����� **�����������** � ������������� ������
- ��������� ����� ������ (`stakedAt`) ����������� ��� ������ ����� ������
- ����������� �������� ����� �������� ������������ ���������� `_minStakeInterval`
- �������� ����������� ����� ����� ������ �� ������� ���������� � ���������� ���������� ���������

### ������� �����������

���������� - ��� ����������� �������, ������� ������� �������������� ������������ � ��������� (�������):

```mermaid
sequenceDiagram
    participant ������������
    participant ������
    participant ��������
    participant Oracle
    
    ������������->>��������: initiateUnstake(validatorId, amount)
    ��������->>��������: �������� ��������� ����������� � ��������� �����
    ��������->>��������: ��������� ����� inUnstakeProcess = true
    ��������-->>������������: ���� ������� UnstakeInitiated(user, validatorId, amount, mpxAmount)
    ��������-->>������������: ���� ������� RewardClaimInitiated(user, validatorId)
    
    Note over ������������,��������: �����: ��� ��������� �������� ������������� ����������� ������� ��������� ������!
    
    ������->>��������: processRewardAndUnstake(user, validatorId, unstakeAmount, rewardAmount)
    ��������->>��������: �������� ������� � ���������� ������ ������
    ��������->>Oracle: ����������� XFI � MPX ��� �������
    ��������->>������������: �������� ����� (������� + �������)
    ��������-->>������������: ���� ������� UnstakeCompleted() � RewardClaimed()
```

**������ ������ �������� �����������:**
- ������������ ����� ���������� ������ ����� ��������� ������� `_minUnstakeInterval` � ������� ���������
- ��� ��������� �������� ������������� ������������ ������� `RewardClaimInitiated`
- �������� ����� ���� �������������� ��������� � ������� ����� `_isUnstakePaused`
- ��� ���������� �������� ������ ���������� ������� `processRewardAndUnstake`, ������� ������������ ������������ ������� � ������� ������

### ������� ��������� ������

��������� ������ ����� ����������� ��� ����������� �������:

```mermaid
sequenceDiagram
    participant ������������
    participant ������
    participant ��������
    
    ������������->>��������: initiateRewardClaim(validatorId)
    ��������->>��������: �������� ��������� ����������� ��� ������ ������
    ��������-->>������������: ���� ������� RewardClaimInitiated(user, validatorId)
    
    ������->>��������: completeRewardClaim(user, validatorId, amount, false) {value: amount}
    ��������->>��������: �������� ������� � ������� ������
    ��������->>������������: �������� ������ ������������
    ��������-->>������������: ���� ������� RewardClaimed(user, validatorId, amount)
```

**������ ������ �������� ��������� ������:**
- ������������ ����� ��������� ������� ������ ����� ��������� ������� `_minClaimInterval` � ������� ���������
- �������� �� ��������� ����������� ����� ������, ��� ��������������� �������
- ������� ����� ���� �������� ��� ��������, ��� � � �������� �����������

### ���������� ����� �������

���������� ����� ������� ��������� ������������ � ������������ �������� ������� ��� ���� ��������:

```mermaid
sequenceDiagram
    participant ������������
    participant ������
    participant ��������
    
    ������������->>��������: initiateEmergencyWithdrawal()
    ��������->>��������: ��������� ����� emergencyWithdrawalRequested = true
    ��������-->>������������: ���� ������� EmergencyWithdrawalInitiated(user)
    
    ������->>��������: completeEmergencyWithdrawal(user, amount)
    ��������->>��������: ������� ���� ������� ������������
    ��������->>������������: �������� ���� ������� ������������
    ��������-->>������������: ���� ������� EmergencyWithdrawalCompleted(user, amount, mpxAmount)
```

**������ ������ ����������� ������:**
- ����� ������� �� ���������� ����� ������������ �� ����� ��������� ������ �������� ���������
- ������� ������� ��� ������ � ������� ������������ � ���������� ��� �����
- ������������ ������ � �������������� ���������, ����� ����������� ���������� ����������

### �������� ����� ������������

�������� ������� ������������, ����� ���������� ��������� �������� �� ������ ���������� � �������:

```mermaid
sequenceDiagram
    participant ������������
    participant ��������
    participant ��������
    
    ��������->>��������: setupValidatorMigration(oldValidatorId, newValidatorId)
    ��������->>��������: ��������� ������� ������� ���������� ��� Deprecated
    
    ������������->>��������: migrateStake(fromValidatorId, toValidatorId)
    ��������->>��������: �������� �������� ����������� (������ - Deprecated, ����� - Enabled)
    ��������->>��������: ������� ������� � ���������� ������ �������
    ��������-->>������������: ���� ������� StakeMigrated(user, fromValidatorId, toValidatorId, amount, mpxAmount)
```

**������ ������ ��������:**
- �������� �������� ������ ���� ������ ��������� ����� ������ `Deprecated`, � ����� - `Enabled`
- ��� �������� ��������� ����� ������ �����������, ��� ���������� ��������� �����������
- ������� �������� ����������� � ���� ���� � �� ������� ������� ���������

## �������������� � ��������

����������� ��������� ������������ ������ �������������� � �������� ��� ����������� ������ ���� �������. ������ ������ ����������� ���� � ���������� ����������� ��������.

### ��������������� �������

��� ����������� ������ ��������� ���������� ������� �������, ������� ��������� ��������� �������:

1. **���������� �����������**:
   - ���������� ������� `UnstakeInitiated`
   - �������� ����������� ���������� ��������
   - ����� ������� `completeUnstake` ��� `processRewardAndUnstake` � ����������� �����������
   - **������ ����� � ����� OPERATOR_ROLE ����� ��������� ��� ��������**

2. **������� ������**:
   - ���������� ������� `RewardClaimInitiated`
   - ��������� ���������� � ����������� �������� �� ������� �����������
   - ������ ����� ������ � ������ �������� � ������ ����������
   - ����� `completeRewardClaim` � ��������� ������������� ���������� XFI
   - **�����:** �������� �� ����� ����������� ������ ������� ������ � �� ����� ��������� ����������� ���������� ����� ��� ������

3. **���������� ����� �������**:
   - ���������� ������� `EmergencyWithdrawalInitiated`
   - �������� ����������� ���������� ����������� ������
   - ����� `completeEmergencyWithdrawal` ��� �������� ���� ������� ������������

```mermaid
sequenceDiagram
    participant ��������
    participant ������
    participant ���������
    
    ��������-->>������: ���� ������� (UnstakeInitiated/RewardClaimInitiated)
    ������->>���������: ������ ���������� � �������� � ������� ����������
    ������->>��������: ����� ��������������� ������� ���������� ��������
    ��������->>��������: �������� ������� � ��������� �������
    ��������->>������������: �������� ������� ������������
    ��������-->>������: ������� � ���������� ��������
```

### ���� ������� � ���������� �������

������ ��������� ��������� ������� � ����������:
1. ������������ ���������� ���������� � ������� ������������� � �����������
2. ����������� ��������� ����������� ��� ���� ����� ��������
3. ��������� ������� ������������� �� ������ ������ �� ����������� ����
4. ������������ ��������� ������� ��������� � ���������� ���������������� ��������
5. ��������� �������������� ������-������, ������� �� �������� � �����-��������

### ����������� ������� ��������������

1. **������������ ������ ���������**:
   - ��������� ����� � ����� OPERATOR_ROLE ������ ���� ������� ��������
   - ������������� ������������� �������������� ��� HSM ��� ��������� ������������

2. **����������� ����������**:
   - ������ ������ ���� ��������������� � ��������
   - ���������� ����������� ��������� ���������� ����������� � ��������������

3. **���������� � ������������**:
   - ���������� ��������� ������� ����������� ���� ������� ���������
   - ����� ���������� ������� ������������ �� ������� ��� ��������� UX

## ����������� XFI/MPX

�������� ���������� ������� ������� ����������� ����� XFI � MPX, ���������� �� ������ Oracle. ��� ����������� ���������� ��� ����������� ������������� ���� � ��������� ��������.

### ������� �����������

```mermaid
sequenceDiagram
    participant ��������
    participant PriceConverter
    participant Oracle
    participant DIA_Oracle
    
    ��������->>PriceConverter: toMPX(oracle, xfiAmount)
    PriceConverter->>Oracle: getPrice("XFI")
    Oracle->>DIA_Oracle: getValue("XFI/USD")
    DIA_Oracle-->>Oracle: (xfiPrice, timestamp)
    Oracle-->>PriceConverter: xfiPrice (18 decimals)
    PriceConverter->>Oracle: getMPXPrice()
    Oracle-->>PriceConverter: mpxPrice (18 decimals)
    PriceConverter->>PriceConverter: mpxAmount = (xfiAmount * xfiPrice) / mpxPrice
    PriceConverter-->>��������: mpxAmount
```

### �������� ���������� ������� �����������

1. **PriceConverter** - ���������� ��� ����������� XFI � MPX
   ```solidity
   // src/libraries/PriceConverter.sol
   function toMPX(IOracle oracle, uint256 xfiAmount) internal view returns (uint256) {
       if (xfiAmount == 0) return 0;
       
       // ��������� ��� �� �������
       uint256 xfiPrice = oracle.getPrice("XFI");
       uint256 mpxPrice = oracle.getMPXPrice();
       
       // ���� �����-���� ���� ����� ����, ����������� ����������
       if (xfiPrice == 0 || mpxPrice == 0) return 0;
       
       // ����������� � �������������� �����-���������: 
       // mpxAmount = xfiAmount * xfiPrice / mpxPrice
       return (xfiAmount * xfiPrice) / mpxPrice;
   }
   ```

2. **UnifiedOracle** - ��������, ������� �������� ������ � ����� � ������������ �� �����������
   - �������� ���� XFI/USD �� DIA Oracle (� 8 ����������� �������)
   - ����������� ��� � ��������� 18 ���������� ������
   - ������ ���� MPX/USD, ��������������� �������
   - �������� ��������� ��������� ��� ������� ������������� DIA Oracle

3. **DIA Oracle** - ������� ������, ��������������� ���������� ������ � ����� XFI/USD

### ������ ����������� �����������

- ��� ���� � ������� �������� � 18 ����������� ������� ��� ������������� � ERC20 ��������
- DIA Oracle ���������� 8 ���������� ������, ������� ��������� �����������
- ���� MPX/USD ����� ���� ����������� ������� ����� ������� `setMPXPrice`
- � ������ ������������� DIA Oracle, ������� ����� ������������ ��������� ��������
- ����������� ������������ ������ ��� ������� � �� ������ �� ������-������ ���������

## �����������

�������� ����� ��� ����������� � ������������, ������� ����� ��������� ��� ���������� � �������������:

### 1. ����������� ������ ������

- **���������� ����������� �����:**
  �������� �� ����� ���������� �������� ����������� ����� ��� ������ ������. ��� ������ ������ ��������������� �� ������ �������.
  
- **���������� ������ ������� ������:**
  �������� �� ������������ ������� ��������������, � ���������� �� ������� �������, ����������� ��������.

### 2. ��������� �����������

- **������������� timestamp ������ ������:**
  �������� ���������� ��������� ����� (timestamp) ������ ������� ������, ��� ����� ���� ���������� ��������� �����������.
  
- **������������� ���������:**
  �� ��������� ����������� ��������� ���������, ������� ����� ���� �������� ����������:
  ```solidity
  _minStakeInterval = 1 days;     // ����������� �������� ����� ��������
  _minUnstakeInterval = 1 days;    // ����������� ����� �� ����������� ��������
  _minClaimInterval = 1 days;      // ����������� ����� �� ����������� ������ ������
  ```

### 3. ����������� ��������

- **�������������� ����� ��� ��������:**
  ��� ������ `initiateUnstake` ������������� ������������ ������� `RewardClaimInitiated`, ��� ������� ��������������� ��������� ��������:
  ```solidity
  // src/core/NativeStaking.sol, ����� initiateUnstake
  // Automatically initiate reward claim for better UX
  emit RewardClaimInitiated(msg.sender, normalizedId);
  ```

### 4. ���������� �������

- **������������� ����������� �����������:**
  ������ ������ ��������� ����������� ��� ������� ��������� ��� ����������� ���������� ������ �������.
  
- **�������� ������� ��� �����������:**
  ```
  - UnstakeInitiated
  - RewardClaimInitiated
  - EmergencyWithdrawalInitiated
  - ValidatorAdded
  - ValidatorUpdated
  ```

### 5. ����������� ���������

- **������������� ��������:**
  ��� ��������� ������ � ���� � ��� �� ���������, ����� ����������� � ������������� ������, � �� ��������� ����� �����:
  ```solidity
  // src/core/NativeStaking.sol, ����� stake
  // Update user stake
  userStake.amount += msg.value;
  userStake.stakedAt = block.timestamp;
  ```

- **����� ��������� �����������:**
  ������ ����� ����� ��������� ��������� �����, ��� ���������� ��� ��������� ����������� ��� �������� � ������ ������.

### 6. ����������� �� �������

- **������������� ����������� �������:**
  ��� ���������� ����������� XFI/MPX ��������� ��������������� ������ � ����������� �������.
  
- **��������� ���������:**
  � ������ ������������� ��������� �������, ������� ����� ������������ ��������� ����, �� �� ����� ������������ ���������.

## ����������� �� �������������

������������� ��������� `NativeStaking` �������� ������������ ���������, ��������� ���������� ��������� � �������������. � ���� ������� ������� ��� ����������� ���� ��� ��������� �������������.

### ��������������� ����������

����� �������������� ����������:
1. ���������� Foundry (forge, cast, anvil)
2. ����� ����������� ���������� ETH/XFI ��� ������ ����
3. ����������� ��������� ����� ��� ��������� � ������� ������

### ���������� ���������� ���������

��� ����������� ������������� ���������� ��������� ��������� ���������� ���������:

```bash
# ��������� ���� ��� ������������� (��� �������� 0x)
export DEV_PRIVATE_KEY=your_private_key_without_0x_prefix

# ��������� ��������� (� ��������)
export MIN_STAKE_INTERVAL=3600    # 1 ���
export MIN_UNSTAKE_INTERVAL=86400 # 1 ����
export MIN_CLAIM_INTERVAL=43200   # 12 �����

# URL RPC-���� ������� ����
export RPC_URL=https://your-rpc-node.url
```

### ������ ������� �������������

��� ������������� �� �������� ��� �������� ���� ����������� ��������� �������:

```bash
forge script script/DeployNativeStaking.s.sol:DeployNativeStaking --broadcast --rpc-url $RPC_URL -vvv
```

��� ���������� ������������ ����� ������������ Anvil:

```bash
# ������ ���������� ����
anvil

# � ������ ��������� ��������� �������������
forge script script/DeployNativeStaking.s.sol:DeployNativeStaking --broadcast --rpc-url http://localhost:8545 -vvv
```

### ������� �������������

������ ������������� ��������� ��������� ����:

1. **������������� ������������:**
   - �������� mock-������� ��� ������������ (� ��������� ����������� ��������� ������)

2. **������������� �������� ����������:**
   - ������������� ������������� `NativeStaking`
   - �������� `ProxyAdmin` ��� ���������� ������
   - ������������� `TransparentUpgradeableProxy` � ������� �������������

3. **��������� ���������:**
   - ������������� ��������� � �����������
   - ��������� ����� ��� ������ �������
   - ��������� ��������� ����������

4. **����� ����������:**
   - ����������� ������� ���� ����������� ����������
   - ���������� � ����������� �����
   - ������������� ��������� ���������

### ������������������ ��������

����� ��������� ������������� ���������� ��������� ��������� ��������:

1. **���������� �����������:**
   ```solidity
   // ���������� ����������� ����� �������
   nativeStaking.addValidator("validator_id", true);
   ```

2. **��������� �������:**
   - ��������� ����������� ������� ���������
   - ��������� ������������ ��� ���������� ��������
   - ���������� � API ����������� ��� ��������� ���������� � ��������

3. **���������� �����:**
   - �������������� ���� OPERATOR_ROLE �������� �������
   - �������������� ���� MANAGER_ROLE ��������������� �������

4. **������ �������:**
   - � ��������-����� ���������� �������� mock-������ �� ��������:
   ```solidity
   nativeStaking.setOracle(address_of_real_oracle);
   ```

### ����������� ����������

����� ������������� ������������� �������������� �����-��������� � ������� ������:

```bash
forge verify-contract <contract_address> <contract_name> --chain <chain_id> --watch
```

## ����������

�������� `NativeStaking` ������������ ����� ������� ������� ��� ��������� XFI � ���������� ���� CrossFi. �� ������������ ���������� � ���������� �������� ���������, ����������� � ������� ������, �� ������� ������� ������� ��� ����������� ������.

�������� ����������� ���������:
- ���������� ����� � ��������������� ����� ���������� �����������
- ����������� �������� ��� ����������� � ��������� ������
- ������ ��������� ��������� ����������� � ����������
- ����������� �������� ������� ����� ������������
- ���������� ����� ������� � ������������ ���������
- ������������� ����� ������-�������

��� �������� ���������� � ������������� ��������� ���������� ���������� ������������ � ��������� ������-�������, ������� ����� ����������������� � ���������� � ������������ ��������������� �������. 