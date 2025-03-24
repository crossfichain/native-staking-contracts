# ����������� �� CrossFi Native Staking

## ����� ����������

CrossFi Native Staking � ��� ������� ��� ��������� ������� XFI, �������� ������������ ���� CrossFi. ������� ���������� ��� ������� ���������:

- **APR ��������**: ������ �������� � ������������� ���������� �������.
- **APY ��������**: �������� ����� vault � �������������� ����������������� ������.

## �������� �������

### ������ � ������

- **XFI** � �������� ����� ���� CrossFi
- **WXFI** � "Wrapped XFI", ERC-20 ������ ������ XFI, ������������ ������ ����������
- **NativeStakingManager** � ����������� �������� ��� ���� �������� ���������
- **NativeStaking** � �������� ��� APR ������ ���������
- **NativeStakingVault** � �������� ��� APY ������ ���������

### ������� � ���������� ������

- **APR (Annual Percentage Rate)** � ������� ���������� ������ ��� ������� ���������
- **APY (Annual Percentage Yield)** � ������� ���������� ���������� ��� vault ��������� � ������ ������������
- **Unbonding Period** � ������ �������������, � ������� �������� ������ ������ ������� ����� ������� ����������� (������ 15 ����)

### ID ��������

������ �������� ���������/����������� ������� ���������� ID ������� (`requestId`), ������� ������������ ��� ������������ ������� ������� � ������������ ��������� �������.

## ��� ����������������� � ��������

### 1. ������ ����������

������ ���������� ����� ������ � �������� ���� CrossFi (������ ���������� �������� ���������):

```
==== CrossFi Native Staking Dev Deployment ====
  Deployer:   0xee2e617a42Aab5be36c290982493C6CC6C072982
  Admin:      0xee2e617a42Aab5be36c290982493C6CC6C072982
  Operator:   0x79F9860d48ef9dDFaF3571281c033664de05E6f5
  Treasury:   0xee2e617a42Aab5be36c290982493C6CC6C072982
  Emergency:  0xee2e617a42Aab5be36c290982493C6CC6C072982
  
==== ������ ���������� ====
  Mock DIA Oracle:        0xdaACec22EA9CDe2E2F711091eB765a480Ace58d6
  WXFI:                   0xDc19cFb2a7B84F887BdbA93388728f5E8371094E
  Oracle Proxy:           0xDd158E533Dda120E32AeB8e4Ce3955A5c6956acB
  APR Staking Proxy:      0xA14C3124a5BB9BAbE3B46232E51192a20ADdc569
  APY Staking Proxy:      0xCD51cFbAAA7E581DaBBBB1ACadd2597C95122f85
  Staking Manager Proxy:  0xbda4FCbd54594c482052f8F6212Df471037bD7ef
  Proxy Admin:            0x5B57f5fF956Ced2d4BEcB856bd84f3b6c2442541
```

**�����**: ��� ���������� ���������� ������������ **������ ����� Staking Manager** (`0xbda4FCbd54594c482052f8F6212Df471037bD7ef`). ��� �������������� � �������� ������ ����������� ����� ���� ��������.

### 2. ������� �������� � APR �������

#### �������� XFI

��� ��������� XFI ������������ ������� `stakeAPR` ��������� NativeStakingManager:

```javascript
// amount - ���������� XFI ��� ��������� (� wei)
// validator - ������������� ���������� (������ "default")
stakingManager.stakeAPR(amount, validator, { value: amount })
```

��� ��������:
- ��������� �������� XFI � ��������
- ������� ������ � ������
- ���������� ID ������� ����� ������� StakedAPR

#### ������ �����������

��� ������� ������ XFI �� ��������� ������������ ������� `unstakeAPR`:

```javascript
// amount - ���������� XFI ��� ����������� (� wei)
// validator - ������������� ���������� (��� ��, ��� ������������� ��� ���������)
stakingManager.unstakeAPR(amount, validator)
```

��� ��������:
- ������� ������ �� ����������
- �������� ������ ������� �������������
- ���������� ID ������� ����� ������� UnstakedAPR

#### ��������� ������� ����� ������� �������������

����� ���������� ������� ������������� ����� �������� ���� XFI:

```javascript
// requestId - ID �������, ���������� ��� ������ unstakeAPR
stakingManager.claimUnstakeAPR(requestId)
```

��� ��������:
- ���������, �������� �� ������ �������������
- ��������� XFI �� ����� ������������
- �������� ������ ��� �����������

#### ��������� ������

��� ��������� ����������� ������ ������������ �������:

```javascript
stakingManager.claimRewardsAPR()
```

### 3. ������� �������� � APY ������� (Vault)

#### �������� � Vault

��� ��������� XFI � vault ������������ ������� `stakeAPY`:

```javascript
// amount - ���������� XFI ��� ��������� (� wei)
stakingManager.stakeAPY(amount, { value: amount })
```

��� ��������:
- ��������� XFI � vault
- ������������ � ���������� ���������� shares (�����)
- ���������� ������� StakedAPY

#### ����� �� Vault

��� ������ ������� �� vault ������������ ������� `withdrawAPY`:

```javascript
// shares - ���������� shares (�����) ��� ������
stakingManager.withdrawAPY(shares)
```

��� ��������:
- ������� ������ �� �����
- �������� ������ ������� �������������
- ���������� ID ������� ����� ������� WithdrawalRequestedAPY

#### ��������� ���������� �������

����� ���������� ������� ������������� ����� �������� ���� XFI:

```javascript
// requestId - ID �������, ���������� ��� ������ withdrawAPY
stakingManager.claimWithdrawalAPY(requestId)
```

## ��������� �������� ���������� ���������

### ����������� � �������������� ����� �����������

CrossFi Native Staking ���������� ����������� � ����������� �����������, �� ������������ ��������������� ������ � ����� � **NativeStakingManager**. ��� ����������� ���������:

1. ��������� �������������� ������������ � ��������
2. ��������������� ��������� �������� � ����������
3. ��������� ��������� ���������� ��� ��������� ����������

��� ������ ������� �������� ����� StakingManager, ������� ����� ���������� �������� ��������������� ����������.

### ��������� �������� �������� ��������� (APR ������)

����� ������������ �������� `stakeAPR(amount, validator)` �� ��������� StakingManager:

1. **StakingManager**:
   - ���������, ��� ����� ��������� ������ ����
   - ���������, ��� validator �� ������ ������
   - ����������� �������� XFI � WXFI
   - �������� ������� `stake(amount, mpxAmount, validator)` �� ��������� NativeStaking

2. **NativeStaking**:
   - ���������, ��� ����������� � StakingManager
   - ������������ ����� ��� ������������
   - ������� ������ � ���������� ID
   - ���������� ������� StakedAPR

3. **���������**:
   - XFI ������������ ��������� � ���������
   - ������������ requestId, ������� ����� �������� �� ������� StakedAPR

### ��������� �������� �������� ����������� (APR ������)

����� ������������ �������� `unstakeAPR(amount, validator)` �� ��������� StakingManager:

1. **StakingManager**:
   - ���������, ��� ���������� �� ��������� (����� Oracle)
   - ���������, ��� ����� ����������� ������ ����
   - ���������, ��� validator �� ������ ������
   - �������� ������� `unstake(user, amount, validator)` �� ��������� NativeStaking

2. **NativeStaking**:
   - ���������, ��� ����������� � StakingManager
   - ���������, ��� � ������������ ���������� XFI � ���������
   - ��������� ������ ��������� ������������
   - ������� ������ �� ���������� � ���������� ID
   - ������������� ����� ������������� = ������� ����� + ������ ������������� (�� Oracle)
   - ���������� ������� UnstakedAPR

3. **���������**:
   - ��������� ������ �� ���������� � requestId
   - ���������� ������ ������� �������������
   - Requestld ����� �������� �� ������� UnstakedAPR

### ��������� �������� �������� ������ ����� ����������� (APR ������)

����� ������������ �������� `claimUnstakeAPR(requestId)` �� ��������� StakingManager:

1. **StakingManager**:
   - ��������� ������������� ������� � ��������� ID
   - ���������, ��� ������ ����������� ����������� ������������
   - ���������, ��� ������ ������������� ����������, ������� `canClaimUnstake(requestId)`
   - �������� ������� `claimUnstake(requestId)` �� ��������� NativeStaking

2. **NativeStaking**:
   - ���������, ��� ����������� � StakingManager
   - �������� ���������� � ������� (�����, ������������)
   - �������� ������ ��� �����������
   - ������������� WXFI ������� � XFI � ���������� ������������
   - ���������� ������� UnstakeClaimedAPR

3. **���������**:
   - ������������ �������� ���� XFI
   - ������ ���������� ��� �����������

### ��������� �������� �������� ��������� ������ (APR ������)

����� ������������ �������� `claimRewardsAPR()` �� ��������� StakingManager:

1. **StakingManager**:
   - �������� ������� `claimRewards(user)` �� ��������� NativeStaking

2. **NativeStaking**:
   - ���������, ��� ����������� � StakingManager
   - ��������� ����������� ������� ������������ �� ������ APR � �������
   - �������� ������� ����������� ������
   - ������������� WXFI � XFI � ���������� ������������
   - ���������� ������� RewardsClaimed

3. **���������**:
   - ������������ �������� ����������� ������� � XFI

### ��������� �������� �������� ��������� (APY ������)

����� ������������ �������� `stakeAPY(amount)` �� ��������� StakingManager:

1. **StakingManager**:
   - ���������, ��� ����� ��������� ������ ����
   - ����������� �������� XFI � WXFI
   - ������� WXFI ��� NativeStakingVault
   - �������� ������� `deposit(amount, user)` �� ��������� NativeStakingVault

2. **NativeStakingVault**:
   - ������������ ���������� shares (�����) �� ������ ����� ��������
   - ��������� WXFI �� ������������ �� ��������
   - ����������� ���������� shares ������������
   - ���������� ������� StakedAPY

3. **���������**:
   - XFI ������������ ��������� � vault
   - ������������ �������� shares, �������������� ��� ���� � vault

### ��������� �������� �������� ������ �� vault (APY ������)

����� ������������ �������� `withdrawAPY(shares)` �� ��������� StakingManager:

1. **StakingManager**:
   - ���������, ��� ���������� shares ������ ����
   - �������� ������� `requestRedeem(shares, user)` �� ��������� NativeStakingVault

2. **NativeStakingVault**:
   - ���������, ��� � ������������ ���������� shares
   - ������������ ���������� ������� (WXFI) �� ������ shares
   - ��������� ���������� shares ������������
   - ������� ������ �� ����� � ���������� ID
   - ������������� ����� ������������� = ������� ����� + ������ �������������
   - ���������� ������� WithdrawalRequestedAPY

3. **���������**:
   - ��������� ������ �� ����� � requestId
   - ���������� ������ ������� �������������
   - RequestId ����� �������� �� ������� WithdrawalRequestedAPY

### ��������� �������� �������� ������ ����� ������ �� vault (APY ������)

����� ������������ �������� `claimWithdrawalAPY(requestId)` �� ��������� StakingManager:

1. **StakingManager**:
   - ��������� ������������� ������� � ��������� ID
   - ���������, ��� ������ ����������� ����������� ������������
   - ���������, ��� ������ ������������� ����������
   - �������� ������� `claimWithdrawal(requestId)` �� ��������� NativeStakingVault

2. **NativeStakingVault**:
   - �������� ���������� � ������� (�����, ������������)
   - �������� ������ ��� �����������
   - ���������� WXFI ������������
   - ������������� WXFI ������� � XFI
   - ���������� ������� WithdrawalClaimedAPY

3. **���������**:
   - ������������ �������� ���� XFI
   - ������ ���������� ��� �����������

## �������� ������� � ��������� ����������

### �������� ������� �������

```javascript
// ��������� ���������� � �������
const request = await stakingManager.getRequest(requestId);

// ��������, ����� �� �������� �������� ����� �����������
const canClaim = await stakingManager.canClaimUnstake(requestId);
```

### ��������� ������ � ��������

```javascript
// ��������� ������� APR ������
const apr = await stakingManager.getAPR();

// ��������� ������� APY ������
const apy = await stakingManager.getAPY();

// ��������� ������� ������������ � APR ������
const balance = await stakingManager.userStakeBalanceAPR(userAddress);

// ��������� ���������� shares ������������ � vault
const shares = await stakingManager.userSharesAPY(userAddress);
```

## ������������ �������

### �������� ������� �������

1. **StakedAPR** � ������ ����� ����� � APR ������
2. **UnstakedAPR** � ������ ������ �� ���������� � APR ������
3. **UnstakeClaimedAPR** � �������� ������� �������� ����� ����������� � APR ������
4. **RewardsClaimed** � �������� ������� � APR ������
5. **StakedAPY** � ������ ����� ����� � Vault (APY ������)
6. **WithdrawalRequestedAPY** � ������ ������ �� ����� �� Vault
7. **WithdrawalClaimedAPY** � �������� ������� �������� �� Vault

������ �������� �� �������:

```javascript
// ������������ ������ ������
stakingManager.on("StakedAPR", (user, amount, mpxAmount, validator, requestId) => {
  console.log(`����� �����: ${user} ��������� ${amount} XFI`);
  console.log(`ID �������: ${requestId}`);
});

// ������������ ������� �� ����������
stakingManager.on("UnstakedAPR", (user, amount, mpxAmount, validator, requestId) => {
  console.log(`������ �� ����������: ${user} ����� ������� ${amount} XFI`);
  console.log(`ID �������: ${requestId}`);
});
```

## ������� ��������

### APR ������ (������ ��������)

1. ������������ ������ �������� XFI ����� `stakeAPR`
2. ������������ ����������� ���������� ����� `unstakeAPR`
3. ����� ������� ������������� ������������ �������� XFI ����� `claimUnstakeAPR`
4. ������������ �������� ������� ����� `claimRewardsAPR`

### APY ������ (Vault)

1. ������������ ������ �������� XFI ����� `stakeAPY` � �������� shares
2. ������� ������������� ��������������� � vault
3. ������������ ����������� ����� ����� `withdrawAPY`
4. ����� ������� ������������� ������������ �������� XFI ����� `claimWithdrawalAPY`

## ������� ������ ���������� (JavaScript)

```javascript
// ������������� ���������� � ���������
const provider = new ethers.providers.JsonRpcProvider("https://rpc.crossfi.org");
const signer = provider.getSigner(); // ��� new ethers.Wallet(privateKey, provider);

// �������� ���������
const stakingManagerAddress = "0xbda4FCbd54594c482052f8F6212Df471037bD7ef"; // ����� StakingManager
const stakingManager = new ethers.Contract(
  stakingManagerAddress,
  stakingManagerABI, // ������������� ABI
  signer
);

// ������� ��� ��������� XFI
async function stakeXFI(amount) {
  // ����������� �� �������� ������� � wei
  const amountInWei = ethers.utils.parseEther(amount);
  
  // ���������� ���������
  const tx = await stakingManager.stakeAPR(amountInWei, "default", {
    value: amountInWei
  });
  
  // �������� ������������� ����������
  const receipt = await tx.wait();
  
  // ��������� ID ������� �� �������
  const event = receipt.events.find(e => e.event === "StakedAPR");
  if (event) {
    const requestId = event.args.requestId.toString();
    console.log("�������� �������! ID �������:", requestId);
  }
}

// ������� ��� ��������� ������
async function claimRewards() {
  const tx = await stakingManager.claimRewardsAPR();
  await tx.wait();
  console.log("������� ������� ��������!");
}
```

## ����� ������ ��� ����������

1. **������ ���������� ID ��������** � ��� ���������� ��� ������������ ��������� ������� ����� ����������� ��� ������ �� vault.

2. **������������ �������** � ������� ������������� ������ ���������� � ������� �������� ���������.

3. **���������� ����������� ������ �������** � ����� ������� ������� ���� `claimUnstakeAPR` ����������� `canClaimUnstake` ��� ��������, �������� �� ������ �������������.

4. **������������� ������** � ������ �������� ����� ����������� ��������, ��������, ��� ������������� ������� ��� ������� ������� �������� �� ��������� ������� �������������.

5. **���������������� ������ � NativeStakingManager** � �� ����������� �������� � ������ ���������� �������. ��� �������� ������ ��������� ����� NativeStakingManager.

## ����������

CrossFi Native Staking ������������� ������ ������� ��������� � ����� ��������� �������� � APR � APY. ��� ���������� ���������� ����������������� ������ � ���������� NativeStakingManager, ������� ������ ������ ������ ����� ��� ���� ��������.

������������ ������ ��������������� ������ � NativeStakingManager, ������� ���������� ������ ��������������� ����������, ��� �������� ���������� � ������������ ���������� ���������, ���� ���� ���������� ������ ���������� ��������� � �������.

��� ���������� ���������� ������� ������������ �������� � ���������� �������� ��� ��������� XFI ������� � ��������� ������, �������� ������������� �������� �������� ���������� ��� ��� ������ ����������. 