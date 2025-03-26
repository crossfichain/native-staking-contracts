# CrossFi Native Staking — Руководство по интеграции

## Содержание

- [Обзор системы](#обзор-системы)
- [Адреса контрактов](#адреса-контрактов)
- [Интеграция для бэкенд-разработчиков](#интеграция-для-бэкенд-разработчиков)
- [Интеграция для фронтенд-разработчиков](#интеграция-для-фронтенд-разработчиков)
- [Рабочие процессы стейкинга](#рабочие-процессы-стейкинга)
- [Управление ID запросов](#управление-id-запросов)
- [События и их обработка](#события-и-их-обработка)
- [Примеры кода](#примеры-кода)

## Обзор системы

Native Staking система CrossFi позволяет пользователям размещать токены XFI в стейкинге двумя способами:

1. **APR модель** — Прямой стейкинг с фиксированной годовой процентной ставкой.
2. **APY модель** — Стейкинг через vault с авто-компаундингом наград.

### Архитектура контрактов

Система состоит из следующих основных контрактов:

- **NativeStakingManager** — Централизованный маршрутизатор для всех операций стейкинга
- **NativeStaking** — Контракт для модели APR
- **NativeStakingVault** — Контракт для модели APY (совместимый с ERC-4626)
- **UnifiedOracle** — Оракул, предоставляющий данные о ценах и информацию о стейкинге
- **WXFI** — Wrapped XFI токен (совместимый с ERC-20)

Все основные контракты реализованы как обновляемые прокси, что позволяет обновлять логику без изменения состояния или адресов контрактов.

## Адреса контрактов

> **Примечание**: После деплоя на тестовую или основную сеть CrossFi, скопируйте адреса из файла `deployments/dev.env`.

```
WXFI_ADDRESS=0x...
DIA_ORACLE_ADDRESS=0x...
ORACLE_PROXY_ADDRESS=0x...
APR_STAKING_PROXY_ADDRESS=0x...
APY_STAKING_PROXY_ADDRESS=0x...
STAKING_MANAGER_PROXY_ADDRESS=0x...
PROXY_ADMIN_ADDRESS=0x...
```

## Интеграция для бэкенд-разработчиков

### Установка и настройка

Для взаимодействия с контрактами на backend рекомендуется использовать библиотеку ethers.js или web3.js.

```javascript
// Пример установки с использованием npm
npm install ethers
```

### Инициализация контрактов

```javascript
const { ethers } = require("ethers");

// Настройка провайдера
const provider = new ethers.providers.JsonRpcProvider("https://rpc.crossfi.org");

// Инициализация основного контракта
const stakingManagerABI = require("./abis/NativeStakingManager.json");
const stakingManagerAddress = "0x..."; // Адрес из deployments/dev.env
const stakingManager = new ethers.Contract(
  stakingManagerAddress, 
  stakingManagerABI, 
  provider
);

// Для транзакций нужен подписант
const privateKey = process.env.PRIVATE_KEY;
const wallet = new ethers.Wallet(privateKey, provider);
const stakingManagerWithSigner = stakingManager.connect(wallet);
```

### Основные функции для бэкенд

1. **Получение данных о стейкинге**

```javascript
// Получение APR ставки
const apr = await stakingManager.getAPR();
console.log("Current APR:", ethers.utils.formatUnits(apr, 18), "%");

// Получение APY ставки
const apy = await stakingManager.getAPY();
console.log("Current APY:", ethers.utils.formatUnits(apy, 18), "%");

// Проверка статуса запроса на анстейкинг
async function checkUnstakeRequest(requestId, userAddress) {
  const request = await stakingManager.getRequest(requestId);
  console.log("Request status:", request);
  
  // Проверка возможности вывода средств
  const canClaim = await stakingManager.canClaimUnstake(requestId);
  console.log("Can be claimed:", canClaim);
}
```

2. **Отслеживание событий**

```javascript
// Отслеживание новых стейкингов
stakingManager.on("StakedAPR", (user, amount, mpxAmount, validator, requestId, event) => {
  console.log(`New stake from ${user}: ${ethers.utils.formatEther(amount)} XFI`);
  console.log(`Request ID: ${requestId}`);
  // Сохранить информацию в БД
});

// Отслеживание запросов на анстейкинг
stakingManager.on("UnstakedAPR", (user, amount, mpxAmount, validator, requestId, event) => {
  console.log(`Unstake request from ${user}: ${ethers.utils.formatEther(amount)} XFI`);
  console.log(`Request ID: ${requestId}`);
  // Обновить статус в БД
});

// Отслеживание выполненных запросов
stakingManager.on("RequestFulfilled", (requestId, requestType, event) => {
  console.log(`Request ${requestId} has been fulfilled`);
  // Обновить статус в БД
});
```

## Интеграция для фронтенд-разработчиков

### Настройка Web3 и контрактов

Для фронтенд-интеграции рекомендуется использовать библиотеку ethers.js или web3.js вместе с Web3Modal или WalletConnect для подключения кошельков.

```javascript
// Пример с использованием ethers.js и React
import { ethers } from "ethers";
import { useState, useEffect } from "react";
import StakingManagerABI from "./abis/NativeStakingManager.json";
import WXFIABI from "./abis/WXFI.json";

const STAKING_MANAGER_ADDRESS = "0x..."; // Адрес из deployments/dev.env
const WXFI_ADDRESS = "0x..."; // Адрес из deployments/dev.env

function StakingApp() {
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [stakingManager, setStakingManager] = useState(null);
  const [wxfi, setWxfi] = useState(null);
  
  // Подключение к MetaMask
  async function connectWallet() {
    if (window.ethereum) {
      try {
        await window.ethereum.request({ method: 'eth_requestAccounts' });
        const provider = new ethers.providers.Web3Provider(window.ethereum);
        const signer = provider.getSigner();
        
        setProvider(provider);
        setSigner(signer);
        
        // Инициализация контрактов
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
  
  // Компонент UI
  return (
    <div>
      <button onClick={connectWallet}>Connect Wallet</button>
      {/* Остальной UI */}
    </div>
  );
}
```

### Основные функции для фронтенда

1. **Стейкинг XFI с использованием APR модели**

```javascript
// Функция для стейкинга XFI
async function stakeXFI(amount, validator = "default") {
  if (!stakingManager || !signer) return;
  
  try {
    // Конвертация amount из человеко-читаемого формата в wei
    const amountInWei = ethers.utils.parseEther(amount);
    
    // Проверка баланса нативного XFI
    const balance = await signer.getBalance();
    if (balance.lt(amountInWei)) {
      alert("Недостаточно XFI на балансе");
      return;
    }
    
    // Выполнение стейкинга
    const tx = await stakingManager.stakeAPR(amountInWei, validator, {
      value: amountInWei // Отправка нативного XFI вместе с транзакцией
    });
    
    // Ожидание подтверждения
    const receipt = await tx.wait();
    
    // Поиск событий StakedAPR в логах транзакции
    const stakedEvent = receipt.events.find(event => event.event === "StakedAPR");
    if (stakedEvent) {
      const requestId = stakedEvent.args.requestId;
      console.log("Staking successful! Request ID:", requestId.toString());
    }
    
    return receipt;
  } catch (error) {
    console.error("Staking error:", error);
    alert("Произошла ошибка при стейкинге. Проверьте консоль для деталей.");
  }
}
```

2. **Анстейкинг XFI из APR модели**

```javascript
// Функция для запроса анстейкинга XFI
async function unstakeXFI(amount, validator = "default") {
  if (!stakingManager || !signer) return;
  
  try {
    // Конвертация amount из человеко-читаемого формата в wei
    const amountInWei = ethers.utils.parseEther(amount);
    
    // Выполнение запроса на анстейкинг
    const tx = await stakingManager.unstakeAPR(amountInWei, validator);
    
    // Ожидание подтверждения
    const receipt = await tx.wait();
    
    // Поиск события UnstakedAPR в логах транзакции
    const unstakedEvent = receipt.events.find(event => event.event === "UnstakedAPR");
    if (unstakedEvent) {
      const requestId = unstakedEvent.args.requestId;
      console.log("Unstaking request successful! Request ID:", requestId.toString());
      // Сохранить requestId для последующего использования
    }
    
    return receipt;
  } catch (error) {
    console.error("Unstaking error:", error);
    alert("Произошла ошибка при анстейкинге. Проверьте консоль для деталей.");
  }
}

// Функция для получения XFI после периода разблокировки
async function claimUnstake(requestId) {
  if (!stakingManager || !signer) return;
  
  try {
    // Проверка, можно ли уже вывести средства
    const canClaim = await stakingManager.canClaimUnstake(requestId);
    if (!canClaim) {
      alert("Период разблокировки еще не завершен");
      return;
    }
    
    // Вывод средств
    const tx = await stakingManager.claimUnstakeAPR(requestId);
    const receipt = await tx.wait();
    
    console.log("Claim successful!");
    return receipt;
  } catch (error) {
    console.error("Claim error:", error);
    alert("Произошла ошибка при выводе средств. Проверьте консоль для деталей.");
  }
}
```

3. **Стейкинг и вывод из APY модели (Vault)**

```javascript
// Стейкинг XFI в vault (APY модель)
async function stakeVault(amount) {
  if (!stakingManager || !signer) return;
  
  try {
    // Конвертация amount из человеко-читаемого формата в wei
    const amountInWei = ethers.utils.parseEther(amount);
    
    // Выполнение стейкинга в vault
    const tx = await stakingManager.stakeAPY(amountInWei, {
      value: amountInWei // Отправка нативного XFI вместе с транзакцией
    });
    
    // Ожидание подтверждения
    const receipt = await tx.wait();
    
    // Поиск события в логах
    const stakedEvent = receipt.events.find(event => event.event === "StakedAPY");
    if (stakedEvent) {
      const shares = stakedEvent.args.shares;
      console.log("Vault staking successful! Shares received:", ethers.utils.formatEther(shares));
    }
    
    return receipt;
  } catch (error) {
    console.error("Vault staking error:", error);
    alert("Произошла ошибка при стейкинге в vault. Проверьте консоль для деталей.");
  }
}

// Вывод из vault (APY модель)
async function withdrawVault(shares) {
  if (!stakingManager || !signer) return;
  
  try {
    // Конвертация shares из человеко-читаемого формата в wei
    const sharesInWei = ethers.utils.parseEther(shares);
    
    // Запрос на вывод средств
    const tx = await stakingManager.withdrawAPY(sharesInWei);
    const receipt = await tx.wait();
    
    // Поиск события WithdrawalRequestedAPY в логах
    const withdrawalEvent = receipt.events.find(event => event.event === "WithdrawalRequestedAPY");
    if (withdrawalEvent) {
      const requestId = withdrawalEvent.args.requestId;
      console.log("Withdrawal request successful! Request ID:", requestId.toString());
      // Сохранить requestId для последующего использования
    }
    
    return receipt;
  } catch (error) {
    console.error("Vault withdrawal error:", error);
    alert("Произошла ошибка при выводе из vault. Проверьте консоль для деталей.");
  }
}

// Получение выведенных средств после периода разблокировки
async function claimWithdrawal(requestId) {
  if (!stakingManager || !signer) return;
  
  try {
    // Вывод средств
    const tx = await stakingManager.claimWithdrawalAPY(requestId);
    const receipt = await tx.wait();
    
    console.log("Withdrawal claim successful!");
    return receipt;
  } catch (error) {
    console.error("Withdrawal claim error:", error);
    alert("Произошла ошибка при получении средств. Проверьте консоль для деталей.");
  }
}
```

## Рабочие процессы стейкинга

### APR модель (прямой стейкинг)

Процесс стейкинга по модели APR включает следующие этапы:

1. **Стейкинг**
   - Пользователь вызывает `stakeAPR(amount, validator)`
   - XFI переводятся на контракт
   - Запись о стейкинге сохраняется в контракте
   - Генерируется событие `StakedAPR`

2. **Запрос анстейкинга**
   - Пользователь вызывает `unstakeAPR(amount, validator)`
   - Создается запрос на анстейкинг с уникальным `requestId`
   - Генерируется событие `UnstakedAPR`
   - Начинается период разблокировки (обычно 21 день)

3. **Получение средств**
   - После завершения периода разблокировки пользователь вызывает `claimUnstakeAPR(requestId)`
   - XFI переводятся обратно пользователю
   - Генерируется событие `UnstakeClaimedAPR`

4. **Получение наград**
   - Пользователь вызывает `claimRewardsAPR()`
   - Рассчитываются и переводятся награды
   - Генерируется событие `RewardsClaimed`

### APY модель (Vault с компаундингом)

Процесс стейкинга по модели APY включает следующие этапы:

1. **Стейкинг**
   - Пользователь вызывает `stakeAPY(amount)`
   - XFI переводятся на контракт
   - Пользователь получает shares (доли) в vault
   - Генерируется событие `StakedAPY`

2. **Вывод средств**
   - Пользователь вызывает `withdrawAPY(shares)`
   - Если в vault достаточно ликвидности, вывод происходит мгновенно
   - В противном случае создается запрос на вывод с `requestId`
   - Генерируется событие `WithdrawalRequestedAPY`
   - Начинается период разблокировки

3. **Получение выведенных средств**
   - После завершения периода разблокировки пользователь вызывает `claimWithdrawalAPY(requestId)`
   - XFI переводятся обратно пользователю
   - Генерируется событие `WithdrawalClaimedAPY`

## Управление ID запросов

ID запросов (`requestId`) используются для отслеживания операций анстейкинга и вывода.

### Прогнозирование ID запросов

Для прогнозирования ID запросов можно использовать функцию:

```javascript
// Прогнозирование ID запроса
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

### Проверка статуса запроса

```javascript
// Проверка статуса запроса
async function checkRequestStatus(requestId) {
  const request = await stakingManager.getRequest(requestId);
  
  // Структура ответа
  const {
    user,            // Адрес пользователя
    amount,          // Количество токенов
    validator,       // ID валидатора
    timestamp,       // Время создания запроса
    unlockTime,      // Время разблокировки
    requestType,     // Тип запроса
    completed        // Выполнен ли запрос
  } = request;
  
  return request;
}
```

## События и их обработка

Система генерирует различные события, которые следует отслеживать:

### События стейкинга APR

- `StakedAPR(address user, uint256 amount, uint256 mpxAmount, string validator, uint256 requestId)`
- `UnstakedAPR(address user, uint256 amount, uint256 mpxAmount, string validator, uint256 requestId)`
- `UnstakeClaimedAPR(address user, uint256 amount, uint256 requestId)`
- `RewardsClaimed(address user, uint256 amount)`

### События стейкинга APY

- `StakedAPY(address user, uint256 assets, uint256 shares)`
- `WithdrawalRequestedAPY(address user, uint256 assets, uint256 shares, uint256 requestId)`
- `WithdrawalClaimedAPY(address user, uint256 assets, uint256 requestId)`

### Общие события

- `RequestCreated(uint256 requestId, address user, uint256 amount, string validator, uint8 requestType)`
- `RequestFulfilled(uint256 requestId, uint8 requestType)`

### Подписка на события

```javascript
// Подписка на все события стейкинга
function subscribeToStakingEvents() {
  // Событие создания стейка APR
  stakingManager.on("StakedAPR", handleStakedAPR);
  
  // Событие запроса анстейкинга APR
  stakingManager.on("UnstakedAPR", handleUnstakedAPR);
  
  // Событие получения средств после анстейкинга APR
  stakingManager.on("UnstakeClaimedAPR", handleUnstakeClaimedAPR);
  
  // Событие стейкинга в vault APY
  stakingManager.on("StakedAPY", handleStakedAPY);
  
  // Событие запроса вывода из vault APY
  stakingManager.on("WithdrawalRequestedAPY", handleWithdrawalRequestedAPY);
  
  // Событие получения средств после вывода из vault APY
  stakingManager.on("WithdrawalClaimedAPY", handleWithdrawalClaimedAPY);
  
  // Событие начисления наград
  stakingManager.on("RewardsClaimed", handleRewardsClaimed);
}

// Обработчики событий
function handleStakedAPR(user, amount, mpxAmount, validator, requestId, event) {
  console.log(`User ${user} staked ${ethers.utils.formatEther(amount)} XFI`);
  // Обновить UI или сохранить информацию
}

// Аналогично для других обработчиков...
```

## Примеры кода

### Полный пример интеграции бэкенда

```javascript
const { ethers } = require("ethers");
const fs = require("fs");

// Загрузка ABI
const stakingManagerABI = JSON.parse(fs.readFileSync("./abis/NativeStakingManager.json"));
const wxfiABI = JSON.parse(fs.readFileSync("./abis/WXFI.json"));
const oracleABI = JSON.parse(fs.readFileSync("./abis/UnifiedOracle.json"));

// Загрузка адресов
const STAKING_MANAGER_ADDRESS = process.env.STAKING_MANAGER_PROXY_ADDRESS;
const WXFI_ADDRESS = process.env.WXFI_ADDRESS;
const ORACLE_ADDRESS = process.env.ORACLE_PROXY_ADDRESS;

// Инициализация провайдера и кошелька
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

// Инициализация контрактов
const stakingManager = new ethers.Contract(STAKING_MANAGER_ADDRESS, stakingManagerABI, wallet);
const wxfi = new ethers.Contract(WXFI_ADDRESS, wxfiABI, wallet);
const oracle = new ethers.Contract(ORACLE_ADDRESS, oracleABI, wallet);

// Пример использования
async function main() {
  try {
    // Получение текущих ставок
    const apr = await oracle.getCurrentAPR();
    const apy = await oracle.getCurrentAPY();
    console.log(`Current APR: ${ethers.utils.formatUnits(apr, 18)}%`);
    console.log(`Current APY: ${ethers.utils.formatUnits(apy, 18)}%`);
    
    // Получение периода разблокировки
    const unbondingPeriod = await oracle.getUnbondingPeriod();
    console.log(`Unbonding period: ${unbondingPeriod / 86400} days`);
    
    // Проверка, заморожен ли анстейкинг
    const isFrozen = await stakingManager.isUnstakingFrozen();
    console.log(`Unstaking frozen: ${isFrozen}`);
    
    // Отслеживание событий
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

### Полный пример компонента фронтенда на React

```jsx
import React, { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import StakingManagerABI from './abis/NativeStakingManager.json';
import WXFIABI from './abis/WXFI.json';

// Адреса контрактов
const STAKING_MANAGER_ADDRESS = process.env.REACT_APP_STAKING_MANAGER_ADDRESS;
const WXFI_ADDRESS = process.env.REACT_APP_WXFI_ADDRESS;

function StakingApp() {
  // Состояние
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
  const [stakingTab, setStakingTab] = useState('apr'); // 'apr' или 'apy'
  
  // Подключение к MetaMask
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
        
        // Инициализация контрактов
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
        
        // Загрузка данных
        loadStakingData(stakingManager);
        
        // Слушаем изменения аккаунта
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
  
  // Загрузка данных о стейкинге
  async function loadStakingData(manager) {
    try {
      // Получение APR и APY
      const apr = await manager.getAPR();
      const apy = await manager.getAPY();
      
      setApr(ethers.utils.formatUnits(apr, 18));
      setApy(ethers.utils.formatUnits(apy, 18));
    } catch (error) {
      console.error("Error loading staking data", error);
    }
  }
  
  // Стейкинг XFI (APR модель)
  async function handleStakeAPR() {
    if (!stakingManager || !stakeAmount) return;
    
    setIsLoading(true);
    try {
      const amountInWei = ethers.utils.parseEther(stakeAmount);
      
      // Выполнение стейкинга
      const tx = await stakingManager.stakeAPR(amountInWei, selectedValidator, {
        value: amountInWei
      });
      
      // Ожидание подтверждения
      await tx.wait();
      
      // Сброс формы
      setStakeAmount('');
      alert("Staking successful!");
    } catch (error) {
      console.error("Staking error:", error);
      alert("Error during staking. Check console for details.");
    } finally {
      setIsLoading(false);
    }
  }
  
  // Запрос анстейкинга XFI (APR модель)
  async function handleUnstakeAPR() {
    if (!stakingManager || !unstakeAmount) return;
    
    setIsLoading(true);
    try {
      const amountInWei = ethers.utils.parseEther(unstakeAmount);
      
      // Запрос на анстейкинг
      const tx = await stakingManager.unstakeAPR(amountInWei, selectedValidator);
      const receipt = await tx.wait();
      
      // Получение requestId из событий
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
  
  // Получение средств после периода разблокировки
  async function handleClaimUnstake() {
    if (!stakingManager || !requestId) return;
    
    setIsLoading(true);
    try {
      // Проверка, можно ли уже вывести средства
      const canClaim = await stakingManager.canClaimUnstake(requestId);
      if (!canClaim) {
        alert("Unbonding period not finished yet");
        return;
      }
      
      // Вывод средств
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
  
  // UI компонента
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
              {/* Аналогичные компоненты для APY стейкинга */}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default StakingApp;
```

## Заключение

Интеграция с Native Staking системой CrossFi требует четкого понимания рабочих процессов стейкинга и обработки событий. Основные моменты для успешной интеграции:

1. **Используйте NativeStakingManager**: Всегда взаимодействуйте с системой через этот контракт
2. **Отслеживайте события**: События содержат важную информацию о ID запросов
3. **Управляйте периодами разблокировки**: Не забывайте проверять возможность вывода средств
4. **Обрабатывайте ошибки**: Каждая операция может потенциально вызвать различные ошибки

При корректной интеграции система обеспечивает надежный и прозрачный механизм для стейкинга XFI токенов и получения наград. 