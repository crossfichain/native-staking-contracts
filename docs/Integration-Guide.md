# CrossFi Native Staking � ����������� �� ����������

## ����������

- [����� �������](#�����-�������)
- [������ ����������](#������-����������)
- [���������� ��� ������-�������������](#����������-���-������-�������������)
- [���������� ��� ��������-�������������](#����������-���-��������-�������������)
- [������� �������� ���������](#�������-��������-���������)
- [���������� ID ��������](#����������-id-��������)
- [������� � �� ���������](#�������-�-��-���������)
- [������� ����](#�������-����)

## ����� �������

Native Staking ������� CrossFi ��������� ������������� ��������� ������ XFI � ��������� ����� ���������:

1. **APR ������** � ������ �������� � ������������� ������� ���������� �������.
2. **APY ������** � �������� ����� vault � ����-������������� ������.

### ����������� ����������

������� ������� �� ��������� �������� ����������:

- **NativeStakingManager** � ���������������� ������������� ��� ���� �������� ���������
- **NativeStaking** � �������� ��� ������ APR
- **NativeStakingVault** � �������� ��� ������ APY (����������� � ERC-4626)
- **UnifiedOracle** � ������, ��������������� ������ � ����� � ���������� � ���������
- **WXFI** � Wrapped XFI ����� (����������� � ERC-20)

��� �������� ��������� ����������� ��� ����������� ������, ��� ��������� ��������� ������ ��� ��������� ��������� ��� ������� ����������.

## ������ ����������

> **����������**: ����� ������ �� �������� ��� �������� ���� CrossFi, ���������� ������ �� ����� `deployments/dev.env`.

```
WXFI_ADDRESS=0x...
DIA_ORACLE_ADDRESS=0x...
ORACLE_PROXY_ADDRESS=0x...
APR_STAKING_PROXY_ADDRESS=0x...
APY_STAKING_PROXY_ADDRESS=0x...
STAKING_MANAGER_PROXY_ADDRESS=0x...
PROXY_ADMIN_ADDRESS=0x...
```

## ���������� ��� ������-�������������

### ��������� � ���������

��� �������������� � ����������� �� backend ������������� ������������ ���������� ethers.js ��� web3.js.

```javascript
// ������ ��������� � �������������� npm
npm install ethers
```

### ������������� ����������

```javascript
const { ethers } = require("ethers");

// ��������� ����������
const provider = new ethers.providers.JsonRpcProvider("https://rpc.crossfi.org");

// ������������� ��������� ���������
const stakingManagerABI = require("./abis/NativeStakingManager.json");
const stakingManagerAddress = "0x..."; // ����� �� deployments/dev.env
const stakingManager = new ethers.Contract(
  stakingManagerAddress, 
  stakingManagerABI, 
  provider
);

// ��� ���������� ����� ���������
const privateKey = process.env.PRIVATE_KEY;
const wallet = new ethers.Wallet(privateKey, provider);
const stakingManagerWithSigner = stakingManager.connect(wallet);
```

### �������� ������� ��� ������

1. **��������� ������ � ���������**

```javascript
// ��������� APR ������
const apr = await stakingManager.getAPR();
console.log("Current APR:", ethers.utils.formatUnits(apr, 18), "%");

// ��������� APY ������
const apy = await stakingManager.getAPY();
console.log("Current APY:", ethers.utils.formatUnits(apy, 18), "%");

// �������� ������� ������� �� ����������
async function checkUnstakeRequest(requestId, userAddress) {
  const request = await stakingManager.getRequest(requestId);
  console.log("Request status:", request);
  
  // �������� ����������� ������ �������
  const canClaim = await stakingManager.canClaimUnstake(requestId);
  console.log("Can be claimed:", canClaim);
}
```

2. **������������ �������**

```javascript
// ������������ ����� ����������
stakingManager.on("StakedAPR", (user, amount, mpxAmount, validator, requestId, event) => {
  console.log(`New stake from ${user}: ${ethers.utils.formatEther(amount)} XFI`);
  console.log(`Request ID: ${requestId}`);
  // ��������� ���������� � ��
});

// ������������ �������� �� ����������
stakingManager.on("UnstakedAPR", (user, amount, mpxAmount, validator, requestId, event) => {
  console.log(`Unstake request from ${user}: ${ethers.utils.formatEther(amount)} XFI`);
  console.log(`Request ID: ${requestId}`);
  // �������� ������ � ��
});

// ������������ ����������� ��������
stakingManager.on("RequestFulfilled", (requestId, requestType, event) => {
  console.log(`Request ${requestId} has been fulfilled`);
  // �������� ������ � ��
});
```

## ���������� ��� ��������-�������������

### ��������� Web3 � ����������

��� ��������-���������� ������������� ������������ ���������� ethers.js ��� web3.js ������ � Web3Modal ��� WalletConnect ��� ����������� ���������.

```javascript
// ������ � �������������� ethers.js � React
import { ethers } from "ethers";
import { useState, useEffect } from "react";
import StakingManagerABI from "./abis/NativeStakingManager.json";
import WXFIABI from "./abis/WXFI.json";

const STAKING_MANAGER_ADDRESS = "0x..."; // ����� �� deployments/dev.env
const WXFI_ADDRESS = "0x..."; // ����� �� deployments/dev.env

function StakingApp() {
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [stakingManager, setStakingManager] = useState(null);
  const [wxfi, setWxfi] = useState(null);
  
  // ����������� � MetaMask
  async function connectWallet() {
    if (window.ethereum) {
      try {
        await window.ethereum.request({ method: 'eth_requestAccounts' });
        const provider = new ethers.providers.Web3Provider(window.ethereum);
        const signer = provider.getSigner();
        
        setProvider(provider);
        setSigner(signer);
        
        // ������������� ����������
        const stakingManager = new ethers.Contract(
          STAKING_MANAGER_ADDRESS,
          StakingManagerABI,
          signer
        );
        
        const wxfi = new ethers.Contract(
          WXFI_ADDRESS,
          WXFIABI,
          signer
        );
        
        setStakingManager(stakingManager);
        setWxfi(wxfi);
      } catch (error) {
        console.error("Error connecting to MetaMask", error);
      }
    } else {
      alert("Please install MetaMask!");
    }
  }
  
  // ��������� UI
  return (
    <div>
      <button onClick={connectWallet}>Connect Wallet</button>
      {/* ��������� UI */}
    </div>
  );
}
```

### �������� ������� ��� ���������

1. **�������� XFI � �������������� APR ������**

```javascript
// ������� ��� ��������� XFI
async function stakeXFI(amount, validator = "default") {
  if (!stakingManager || !signer) return;
  
  try {
    // ����������� amount �� ��������-��������� ������� � wei
    const amountInWei = ethers.utils.parseEther(amount);
    
    // �������� ������� ��������� XFI
    const balance = await signer.getBalance();
    if (balance.lt(amountInWei)) {
      alert("������������ XFI �� �������");
      return;
    }
    
    // ���������� ���������
    const tx = await stakingManager.stakeAPR(amountInWei, validator, {
      value: amountInWei // �������� ��������� XFI ������ � �����������
    });
    
    // �������� �������������
    const receipt = await tx.wait();
    
    // ����� ������� StakedAPR � ����� ����������
    const stakedEvent = receipt.events.find(event => event.event === "StakedAPR");
    if (stakedEvent) {
      const requestId = stakedEvent.args.requestId;
      console.log("Staking successful! Request ID:", requestId.toString());
    }
    
    return receipt;
  } catch (error) {
    console.error("Staking error:", error);
    alert("��������� ������ ��� ���������. ��������� ������� ��� �������.");
  }
}
```

2. **���������� XFI �� APR ������**

```javascript
// ������� ��� ������� ����������� XFI
async function unstakeXFI(amount, validator = "default") {
  if (!stakingManager || !signer) return;
  
  try {
    // ����������� amount �� ��������-��������� ������� � wei
    const amountInWei = ethers.utils.parseEther(amount);
    
    // ���������� ������� �� ����������
    const tx = await stakingManager.unstakeAPR(amountInWei, validator);
    
    // �������� �������������
    const receipt = await tx.wait();
    
    // ����� ������� UnstakedAPR � ����� ����������
    const unstakedEvent = receipt.events.find(event => event.event === "UnstakedAPR");
    if (unstakedEvent) {
      const requestId = unstakedEvent.args.requestId;
      console.log("Unstaking request successful! Request ID:", requestId.toString());
      // ��������� requestId ��� ������������ �������������
    }
    
    return receipt;
  } catch (error) {
    console.error("Unstaking error:", error);
    alert("��������� ������ ��� �����������. ��������� ������� ��� �������.");
  }
}

// ������� ��� ��������� XFI ����� ������� �������������
async function claimUnstake(requestId) {
  if (!stakingManager || !signer) return;
  
  try {
    // ��������, ����� �� ��� ������� ��������
    const canClaim = await stakingManager.canClaimUnstake(requestId);
    if (!canClaim) {
      alert("������ ������������� ��� �� ��������");
      return;
    }
    
    // ����� �������
    const tx = await stakingManager.claimUnstakeAPR(requestId);
    const receipt = await tx.wait();
    
    console.log("Claim successful!");
    return receipt;
  } catch (error) {
    console.error("Claim error:", error);
    alert("��������� ������ ��� ������ �������. ��������� ������� ��� �������.");
  }
}
```

3. **�������� � ����� �� APY ������ (Vault)**

```javascript
// �������� XFI � vault (APY ������)
async function stakeVault(amount) {
  if (!stakingManager || !signer) return;
  
  try {
    // ����������� amount �� ��������-��������� ������� � wei
    const amountInWei = ethers.utils.parseEther(amount);
    
    // ���������� ��������� � vault
    const tx = await stakingManager.stakeAPY(amountInWei, {
      value: amountInWei // �������� ��������� XFI ������ � �����������
    });
    
    // �������� �������������
    const receipt = await tx.wait();
    
    // ����� ������� � �����
    const stakedEvent = receipt.events.find(event => event.event === "StakedAPY");
    if (stakedEvent) {
      const shares = stakedEvent.args.shares;
      console.log("Vault staking successful! Shares received:", ethers.utils.formatEther(shares));
    }
    
    return receipt;
  } catch (error) {
    console.error("Vault staking error:", error);
    alert("��������� ������ ��� ��������� � vault. ��������� ������� ��� �������.");
  }
}

// ����� �� vault (APY ������)
async function withdrawVault(shares) {
  if (!stakingManager || !signer) return;
  
  try {
    // ����������� shares �� ��������-��������� ������� � wei
    const sharesInWei = ethers.utils.parseEther(shares);
    
    // ������ �� ����� �������
    const tx = await stakingManager.withdrawAPY(sharesInWei);
    const receipt = await tx.wait();
    
    // ����� ������� WithdrawalRequestedAPY � �����
    const withdrawalEvent = receipt.events.find(event => event.event === "WithdrawalRequestedAPY");
    if (withdrawalEvent) {
      const requestId = withdrawalEvent.args.requestId;
      console.log("Withdrawal request successful! Request ID:", requestId.toString());
      // ��������� requestId ��� ������������ �������������
    }
    
    return receipt;
  } catch (error) {
    console.error("Vault withdrawal error:", error);
    alert("��������� ������ ��� ������ �� vault. ��������� ������� ��� �������.");
  }
}

// ��������� ���������� ������� ����� ������� �������������
async function claimWithdrawal(requestId) {
  if (!stakingManager || !signer) return;
  
  try {
    // ����� �������
    const tx = await stakingManager.claimWithdrawalAPY(requestId);
    const receipt = await tx.wait();
    
    console.log("Withdrawal claim successful!");
    return receipt;
  } catch (error) {
    console.error("Withdrawal claim error:", error);
    alert("��������� ������ ��� ��������� �������. ��������� ������� ��� �������.");
  }
}
```

## ������� �������� ���������

### APR ������ (������ ��������)

������� ��������� �� ������ APR �������� ��������� �����:

1. **��������**
   - ������������ �������� `stakeAPR(amount, validator)`
   - XFI ����������� �� ��������
   - ������ � ��������� ����������� � ���������
   - ������������ ������� `StakedAPR`

2. **������ �����������**
   - ������������ �������� `unstakeAPR(amount, validator)`
   - ��������� ������ �� ���������� � ���������� `requestId`
   - ������������ ������� `UnstakedAPR`
   - ���������� ������ ������������� (������ 21 ����)

3. **��������� �������**
   - ����� ���������� ������� ������������� ������������ �������� `claimUnstakeAPR(requestId)`
   - XFI ����������� ������� ������������
   - ������������ ������� `UnstakeClaimedAPR`

4. **��������� ������**
   - ������������ �������� `claimRewardsAPR()`
   - �������������� � ����������� �������
   - ������������ ������� `RewardsClaimed`

### APY ������ (Vault � �������������)

������� ��������� �� ������ APY �������� ��������� �����:

1. **��������**
   - ������������ �������� `stakeAPY(amount)`
   - XFI ����������� �� ��������
   - ������������ �������� shares (����) � vault
   - ������������ ������� `StakedAPY`

2. **����� �������**
   - ������������ �������� `withdrawAPY(shares)`
   - ���� � vault ���������� �����������, ����� ���������� ���������
   - � ��������� ������ ��������� ������ �� ����� � `requestId`
   - ������������ ������� `WithdrawalRequestedAPY`
   - ���������� ������ �������������

3. **��������� ���������� �������**
   - ����� ���������� ������� ������������� ������������ �������� `claimWithdrawalAPY(requestId)`
   - XFI ����������� ������� ������������
   - ������������ ������� `WithdrawalClaimedAPY`

## ���������� ID ��������

ID �������� (`requestId`) ������������ ��� ������������ �������� ����������� � ������.

### ��������������� ID ��������

��� ��������������� ID �������� ����� ������������ �������:

```javascript
// ��������������� ID �������
async function predictRequestId(user, amount, validator, requestType) {
  const predictedId = await stakingManager.predictRequestId(
    user,
    amount,
    validator,
    requestType // 0 = STAKE, 1 = UNSTAKE, 2 = WITHDRAWAL
  );
  return predictedId;
}
```

### �������� ������� �������

```javascript
// �������� ������� �������
async function checkRequestStatus(requestId) {
  const request = await stakingManager.getRequest(requestId);
  
  // ��������� ������
  const {
    user,            // ����� ������������
    amount,          // ���������� �������
    validator,       // ID ����������
    timestamp,       // ����� �������� �������
    unlockTime,      // ����� �������������
    requestType,     // ��� �������
    completed        // �������� �� ������
  } = request;
  
  return request;
}
```

## ������� � �� ���������

������� ���������� ��������� �������, ������� ������� �����������:

### ������� ��������� APR

- `StakedAPR(address user, uint256 amount, uint256 mpxAmount, string validator, uint256 requestId)`
- `UnstakedAPR(address user, uint256 amount, uint256 mpxAmount, string validator, uint256 requestId)`
- `UnstakeClaimedAPR(address user, uint256 amount, uint256 requestId)`
- `RewardsClaimed(address user, uint256 amount)`

### ������� ��������� APY

- `StakedAPY(address user, uint256 assets, uint256 shares)`
- `WithdrawalRequestedAPY(address user, uint256 assets, uint256 shares, uint256 requestId)`
- `WithdrawalClaimedAPY(address user, uint256 assets, uint256 requestId)`

### ����� �������

- `RequestCreated(uint256 requestId, address user, uint256 amount, string validator, uint8 requestType)`
- `RequestFulfilled(uint256 requestId, uint8 requestType)`

### �������� �� �������

```javascript
// �������� �� ��� ������� ���������
function subscribeToStakingEvents() {
  // ������� �������� ������ APR
  stakingManager.on("StakedAPR", handleStakedAPR);
  
  // ������� ������� ����������� APR
  stakingManager.on("UnstakedAPR", handleUnstakedAPR);
  
  // ������� ��������� ������� ����� ����������� APR
  stakingManager.on("UnstakeClaimedAPR", handleUnstakeClaimedAPR);
  
  // ������� ��������� � vault APY
  stakingManager.on("StakedAPY", handleStakedAPY);
  
  // ������� ������� ������ �� vault APY
  stakingManager.on("WithdrawalRequestedAPY", handleWithdrawalRequestedAPY);
  
  // ������� ��������� ������� ����� ������ �� vault APY
  stakingManager.on("WithdrawalClaimedAPY", handleWithdrawalClaimedAPY);
  
  // ������� ���������� ������
  stakingManager.on("RewardsClaimed", handleRewardsClaimed);
}

// ����������� �������
function handleStakedAPR(user, amount, mpxAmount, validator, requestId, event) {
  console.log(`User ${user} staked ${ethers.utils.formatEther(amount)} XFI`);
  // �������� UI ��� ��������� ����������
}

// ���������� ��� ������ ������������...
```

## ������� ����

### ������ ������ ���������� �������

```javascript
const { ethers } = require("ethers");
const fs = require("fs");

// �������� ABI
const stakingManagerABI = JSON.parse(fs.readFileSync("./abis/NativeStakingManager.json"));
const wxfiABI = JSON.parse(fs.readFileSync("./abis/WXFI.json"));
const oracleABI = JSON.parse(fs.readFileSync("./abis/UnifiedOracle.json"));

// �������� �������
const STAKING_MANAGER_ADDRESS = process.env.STAKING_MANAGER_PROXY_ADDRESS;
const WXFI_ADDRESS = process.env.WXFI_ADDRESS;
const ORACLE_ADDRESS = process.env.ORACLE_PROXY_ADDRESS;

// ������������� ���������� � ��������
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

// ������������� ����������
const stakingManager = new ethers.Contract(STAKING_MANAGER_ADDRESS, stakingManagerABI, wallet);
const wxfi = new ethers.Contract(WXFI_ADDRESS, wxfiABI, wallet);
const oracle = new ethers.Contract(ORACLE_ADDRESS, oracleABI, wallet);

// ������ �������������
async function main() {
  try {
    // ��������� ������� ������
    const apr = await oracle.getCurrentAPR();
    const apy = await oracle.getCurrentAPY();
    console.log(`Current APR: ${ethers.utils.formatUnits(apr, 18)}%`);
    console.log(`Current APY: ${ethers.utils.formatUnits(apy, 18)}%`);
    
    // ��������� ������� �������������
    const unbondingPeriod = await oracle.getUnbondingPeriod();
    console.log(`Unbonding period: ${unbondingPeriod / 86400} days`);
    
    // ��������, ��������� �� ����������
    const isFrozen = await stakingManager.isUnstakingFrozen();
    console.log(`Unstaking frozen: ${isFrozen}`);
    
    // ������������ �������
    stakingManager.on("StakedAPR", (user, amount, mpxAmount, validator, requestId, event) => {
      console.log(`New stake: ${user} staked ${ethers.utils.formatEther(amount)} XFI`);
      console.log(`Request ID: ${requestId}`);
    });
    
    console.log("Backend integration initialized successfully!");
  } catch (error) {
    console.error("Initialization error:", error);
  }
}

main();
```

### ������ ������ ���������� ��������� �� React

```jsx
import React, { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import StakingManagerABI from './abis/NativeStakingManager.json';
import WXFIABI from './abis/WXFI.json';

// ������ ����������
const STAKING_MANAGER_ADDRESS = process.env.REACT_APP_STAKING_MANAGER_ADDRESS;
const WXFI_ADDRESS = process.env.REACT_APP_WXFI_ADDRESS;

function StakingApp() {
  // ���������
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [account, setAccount] = useState('');
  const [stakingManager, setStakingManager] = useState(null);
  const [wxfi, setWxfi] = useState(null);
  const [apr, setApr] = useState('0');
  const [apy, setApy] = useState('0');
  const [stakeAmount, setStakeAmount] = useState('');
  const [unstakeAmount, setUnstakeAmount] = useState('');
  const [requestId, setRequestId] = useState('');
  const [validators, setValidators] = useState(['default']);
  const [selectedValidator, setSelectedValidator] = useState('default');
  const [isLoading, setIsLoading] = useState(false);
  const [stakingTab, setStakingTab] = useState('apr'); // 'apr' ��� 'apy'
  
  // ����������� � MetaMask
  async function connectWallet() {
    if (window.ethereum) {
      try {
        await window.ethereum.request({ method: 'eth_requestAccounts' });
        const provider = new ethers.providers.Web3Provider(window.ethereum);
        const signer = provider.getSigner();
        const account = await signer.getAddress();
        
        setProvider(provider);
        setSigner(signer);
        setAccount(account);
        
        // ������������� ����������
        const stakingManager = new ethers.Contract(
          STAKING_MANAGER_ADDRESS,
          StakingManagerABI,
          signer
        );
        
        const wxfi = new ethers.Contract(
          WXFI_ADDRESS,
          WXFIABI,
          signer
        );
        
        setStakingManager(stakingManager);
        setWxfi(wxfi);
        
        // �������� ������
        loadStakingData(stakingManager);
        
        // ������� ��������� ��������
        window.ethereum.on('accountsChanged', (accounts) => {
          setAccount(accounts[0]);
        });
      } catch (error) {
        console.error("Error connecting to MetaMask", error);
      }
    } else {
      alert("Please install MetaMask!");
    }
  }
  
  // �������� ������ � ���������
  async function loadStakingData(manager) {
    try {
      // ��������� APR � APY
      const apr = await manager.getAPR();
      const apy = await manager.getAPY();
      
      setApr(ethers.utils.formatUnits(apr, 18));
      setApy(ethers.utils.formatUnits(apy, 18));
    } catch (error) {
      console.error("Error loading staking data", error);
    }
  }
  
  // �������� XFI (APR ������)
  async function handleStakeAPR() {
    if (!stakingManager || !stakeAmount) return;
    
    setIsLoading(true);
    try {
      const amountInWei = ethers.utils.parseEther(stakeAmount);
      
      // ���������� ���������
      const tx = await stakingManager.stakeAPR(amountInWei, selectedValidator, {
        value: amountInWei
      });
      
      // �������� �������������
      await tx.wait();
      
      // ����� �����
      setStakeAmount('');
      alert("Staking successful!");
    } catch (error) {
      console.error("Staking error:", error);
      alert("Error during staking. Check console for details.");
    } finally {
      setIsLoading(false);
    }
  }
  
  // ������ ����������� XFI (APR ������)
  async function handleUnstakeAPR() {
    if (!stakingManager || !unstakeAmount) return;
    
    setIsLoading(true);
    try {
      const amountInWei = ethers.utils.parseEther(unstakeAmount);
      
      // ������ �� ����������
      const tx = await stakingManager.unstakeAPR(amountInWei, selectedValidator);
      const receipt = await tx.wait();
      
      // ��������� requestId �� �������
      const event = receipt.events.find(e => e.event === "UnstakedAPR");
      if (event) {
        const id = event.args.requestId.toString();
        setRequestId(id);
        alert(`Unstaking request submitted. Request ID: ${id}`);
      }
      
      setUnstakeAmount('');
    } catch (error) {
      console.error("Unstaking error:", error);
      alert("Error during unstaking. Check console for details.");
    } finally {
      setIsLoading(false);
    }
  }
  
  // ��������� ������� ����� ������� �������������
  async function handleClaimUnstake() {
    if (!stakingManager || !requestId) return;
    
    setIsLoading(true);
    try {
      // ��������, ����� �� ��� ������� ��������
      const canClaim = await stakingManager.canClaimUnstake(requestId);
      if (!canClaim) {
        alert("Unbonding period not finished yet");
        return;
      }
      
      // ����� �������
      const tx = await stakingManager.claimUnstakeAPR(requestId);
      await tx.wait();
      
      alert("Claim successful!");
      setRequestId('');
    } catch (error) {
      console.error("Claim error:", error);
      alert("Error during claim. Check console for details.");
    } finally {
      setIsLoading(false);
    }
  }
  
  // UI ����������
  return (
    <div className="staking-container">
      <h1>CrossFi Native Staking</h1>
      
      {!account ? (
        <button onClick={connectWallet}>Connect Wallet</button>
      ) : (
        <div>
          <div className="account-info">
            <p>Connected Account: {account}</p>
            <p>Current APR: {apr}%</p>
            <p>Current APY: {apy}%</p>
          </div>
          
          <div className="staking-tabs">
            <button
              className={stakingTab === 'apr' ? 'active' : ''}
              onClick={() => setStakingTab('apr')}
            >
              APR Staking
            </button>
            <button
              className={stakingTab === 'apy' ? 'active' : ''}
              onClick={() => setStakingTab('apy')}
            >
              APY Staking (Vault)
            </button>
          </div>
          
          {stakingTab === 'apr' ? (
            <div className="apr-staking">
              <h2>APR Staking</h2>
              
              <div className="form-group">
                <label>Validator:</label>
                <select
                  value={selectedValidator}
                  onChange={(e) => setSelectedValidator(e.target.value)}
                >
                  {validators.map(validator => (
                    <option key={validator} value={validator}>{validator}</option>
                  ))}
                </select>
              </div>
              
              <div className="form-group">
                <label>Stake Amount (XFI):</label>
                <input
                  type="number"
                  value={stakeAmount}
                  onChange={(e) => setStakeAmount(e.target.value)}
                  placeholder="Amount to stake"
                />
                <button 
                  onClick={handleStakeAPR}
                  disabled={isLoading || !stakeAmount}
                >
                  {isLoading ? 'Processing...' : 'Stake XFI'}
                </button>
              </div>
              
              <div className="form-group">
                <label>Unstake Amount (XFI):</label>
                <input
                  type="number"
                  value={unstakeAmount}
                  onChange={(e) => setUnstakeAmount(e.target.value)}
                  placeholder="Amount to unstake"
                />
                <button 
                  onClick={handleUnstakeAPR}
                  disabled={isLoading || !unstakeAmount}
                >
                  {isLoading ? 'Processing...' : 'Request Unstake'}
                </button>
              </div>
              
              <div className="form-group">
                <label>Claim Unstake:</label>
                <input
                  type="text"
                  value={requestId}
                  onChange={(e) => setRequestId(e.target.value)}
                  placeholder="Request ID"
                />
                <button 
                  onClick={handleClaimUnstake}
                  disabled={isLoading || !requestId}
                >
                  {isLoading ? 'Processing...' : 'Claim Unstaked XFI'}
                </button>
              </div>
            </div>
          ) : (
            <div className="apy-staking">
              <h2>APY Vault Staking</h2>
              {/* ����������� ���������� ��� APY ��������� */}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default StakingApp;
```

## ����������

���������� � Native Staking �������� CrossFi ������� ������� ��������� ������� ��������� ��������� � ��������� �������. �������� ������� ��� �������� ����������:

1. **����������� NativeStakingManager**: ������ ���������������� � �������� ����� ���� ��������
2. **������������ �������**: ������� �������� ������ ���������� � ID ��������
3. **���������� ��������� �������������**: �� ��������� ��������� ����������� ������ �������
4. **������������� ������**: ������ �������� ����� ������������ ������� ��������� ������

��� ���������� ���������� ������� ������������ �������� � ���������� �������� ��� ��������� XFI ������� � ��������� ������. 