# Руководство по CrossFi Native Staking

## Общая информация

CrossFi Native Staking — это система для стейкинга токенов XFI, нативной криптовалюты сети CrossFi. Система предлагает два способа стейкинга:

- **APR стейкинг**: Прямой стейкинг с фиксированной процентной ставкой.
- **APY стейкинг**: Стейкинг через vault с автоматическим реинвестированием наград.

## Основные понятия

### Токены и адреса

- **XFI** — Нативный токен сети CrossFi
- **WXFI** — "Wrapped XFI", ERC-20 версия токена XFI, используемая внутри контрактов
- **NativeStakingManager** — Центральный контракт для всех операций стейкинга
- **NativeStaking** — Контракт для APR модели стейкинга
- **NativeStakingVault** — Контракт для APY модели стейкинга

### Периоды и процентные ставки

- **APR (Annual Percentage Rate)** — Годовая процентная ставка для прямого стейкинга
- **APY (Annual Percentage Yield)** — Годовая процентная доходность для vault стейкинга с учетом компаундинга
- **Unbonding Period** — Период разблокировки, в течение которого токены нельзя вывести после запроса анстейкинга (обычно 15 дней)

### ID запросов

Каждая операция стейкинга/анстейкинга создает уникальный ID запроса (`requestId`), который используется для отслеживания статуса запроса и последующего получения средств.

## Как взаимодействовать с системой

### 1. Адреса контрактов

Адреса контрактов после деплоя в тестовую сеть CrossFi (пример актуальной тестовой установки):

```
==== CrossFi Native Staking Dev Deployment ====
  Deployer:   0xee2e617a42Aab5be36c290982493C6CC6C072982
  Admin:      0xee2e617a42Aab5be36c290982493C6CC6C072982
  Operator:   0x79F9860d48ef9dDFaF3571281c033664de05E6f5
  Treasury:   0xee2e617a42Aab5be36c290982493C6CC6C072982
  Emergency:  0xee2e617a42Aab5be36c290982493C6CC6C072982
  
==== Адреса контрактов ====
  Mock DIA Oracle:        0xdaACec22EA9CDe2E2F711091eB765a480Ace58d6
  WXFI:                   0xDc19cFb2a7B84F887BdbA93388728f5E8371094E
  Oracle Proxy:           0xDd158E533Dda120E32AeB8e4Ce3955A5c6956acB
  APR Staking Proxy:      0xA14C3124a5BB9BAbE3B46232E51192a20ADdc569
  APY Staking Proxy:      0xCD51cFbAAA7E581DaBBBB1ACadd2597C95122f85
  Staking Manager Proxy:  0xbda4FCbd54594c482052f8F6212Df471037bD7ef
  Proxy Admin:            0x5B57f5fF956Ced2d4BEcB856bd84f3b6c2442541
```

**ВАЖНО**: Для интеграции необходимо использовать **только адрес Staking Manager** (`0xbda4FCbd54594c482052f8F6212Df471037bD7ef`). Все взаимодействия с системой должны происходить через этот контракт.

### 2. Базовые операции с APR моделью

#### Стейкинг XFI

Для стейкинга XFI используется функция `stakeAPR` контракта NativeStakingManager:

```javascript
// amount - количество XFI для стейкинга (в wei)
// validator - идентификатор валидатора (обычно "default")
stakingManager.stakeAPR(amount, validator, { value: amount })
```

Эта операция:
- Переводит нативные XFI в контракт
- Создает запись о стейке
- Возвращает ID запроса через событие StakedAPR

#### Запрос анстейкинга

Для запроса вывода XFI из стейкинга используется функция `unstakeAPR`:

```javascript
// amount - количество XFI для анстейкинга (в wei)
// validator - идентификатор валидатора (тот же, что использовался при стейкинге)
stakingManager.unstakeAPR(amount, validator)
```

Эта операция:
- Создает запрос на анстейкинг
- Начинает отсчет периода разблокировки
- Возвращает ID запроса через событие UnstakedAPR

#### Получение средств после периода разблокировки

После завершения периода разблокировки можно получить свои XFI:

```javascript
// requestId - ID запроса, полученный при вызове unstakeAPR
stakingManager.claimUnstakeAPR(requestId)
```

Эта операция:
- Проверяет, завершен ли период разблокировки
- Переводит XFI на адрес пользователя
- Отмечает запрос как выполненный

#### Получение наград

Для получения накопленных наград используется функция:

```javascript
stakingManager.claimRewardsAPR()
```

### 3. Базовые операции с APY моделью (Vault)

#### Стейкинг в Vault

Для стейкинга XFI в vault используется функция `stakeAPY`:

```javascript
// amount - количество XFI для стейкинга (в wei)
stakingManager.stakeAPY(amount, { value: amount })
```

Эта операция:
- Переводит XFI в vault
- Рассчитывает и возвращает количество shares (долей)
- Генерирует событие StakedAPY

#### Вывод из Vault

Для вывода средств из vault используется функция `withdrawAPY`:

```javascript
// shares - количество shares (долей) для вывода
stakingManager.withdrawAPY(shares)
```

Эта операция:
- Создает запрос на вывод
- Начинает отсчет периода разблокировки
- Возвращает ID запроса через событие WithdrawalRequestedAPY

#### Получение выведенных средств

После завершения периода разблокировки можно получить свои XFI:

```javascript
// requestId - ID запроса, полученный при вызове withdrawAPY
stakingManager.claimWithdrawalAPY(requestId)
```

## Подробное описание внутренних процессов

### Архитектура и взаимодействие между контрактами

CrossFi Native Staking использует архитектуру с несколькими контрактами, но пользователь взаимодействует только с одним — **NativeStakingManager**. Эта архитектура позволяет:

1. Упростить взаимодействие пользователя с системой
2. Централизованно управлять доступом и проверками
3. Обновлять отдельные компоненты без изменения интерфейса

Все вызовы функций проходят через StakingManager, который затем делегирует операции соответствующим контрактам.

### Детальное описание процесса стейкинга (APR модель)

Когда пользователь вызывает `stakeAPR(amount, validator)` на контракте StakingManager:

1. **StakingManager**:
   - Проверяет, что сумма стейкинга больше нуля
   - Проверяет, что validator не пустая строка
   - Оборачивает нативные XFI в WXFI
   - Вызывает функцию `stake(amount, mpxAmount, validator)` на контракте NativeStaking

2. **NativeStaking**:
   - Проверяет, что отправитель — StakingManager
   - Регистрирует стейк для пользователя
   - Создает запрос с уникальным ID
   - Генерирует событие StakedAPR

3. **Результат**:
   - XFI пользователя размещены в стейкинге
   - Генерируется requestId, который можно получить из события StakedAPR

### Детальное описание процесса анстейкинга (APR модель)

Когда пользователь вызывает `unstakeAPR(amount, validator)` на контракте StakingManager:

1. **StakingManager**:
   - Проверяет, что анстейкинг не заморожен (через Oracle)
   - Проверяет, что сумма анстейкинга больше нуля
   - Проверяет, что validator не пустая строка
   - Вызывает функцию `unstake(user, amount, validator)` на контракте NativeStaking

2. **NativeStaking**:
   - Проверяет, что отправитель — StakingManager
   - Проверяет, что у пользователя достаточно XFI в стейкинге
   - Уменьшает баланс стейкинга пользователя
   - Создает запрос на анстейкинг с уникальным ID
   - Устанавливает время разблокировки = текущее время + период разблокировки (из Oracle)
   - Генерирует событие UnstakedAPR

3. **Результат**:
   - Создается запрос на анстейкинг с requestId
   - Начинается отсчет периода разблокировки
   - Requestld можно получить из события UnstakedAPR

### Детальное описание процесса клейма после анстейкинга (APR модель)

Когда пользователь вызывает `claimUnstakeAPR(requestId)` на контракте StakingManager:

1. **StakingManager**:
   - Проверяет существование запроса с указанным ID
   - Проверяет, что запрос принадлежит вызывающему пользователю
   - Проверяет, что период разблокировки завершился, вызывая `canClaimUnstake(requestId)`
   - Вызывает функцию `claimUnstake(requestId)` на контракте NativeStaking

2. **NativeStaking**:
   - Проверяет, что отправитель — StakingManager
   - Получает информацию о запросе (сумма, пользователь)
   - Отмечает запрос как выполненный
   - Разворачивает WXFI обратно в XFI и отправляет пользователю
   - Генерирует событие UnstakeClaimedAPR

3. **Результат**:
   - Пользователь получает свои XFI
   - Запрос отмечается как выполненный

### Детальное описание процесса получения наград (APR модель)

Когда пользователь вызывает `claimRewardsAPR()` на контракте StakingManager:

1. **StakingManager**:
   - Вызывает функцию `claimRewards(user)` на контракте NativeStaking

2. **NativeStaking**:
   - Проверяет, что отправитель — StakingManager
   - Вычисляет накопленные награды пользователя на основе APR и времени
   - Обнуляет счетчик накопленных наград
   - Разворачивает WXFI в XFI и отправляет пользователю
   - Генерирует событие RewardsClaimed

3. **Результат**:
   - Пользователь получает накопленные награды в XFI

### Детальное описание процесса стейкинга (APY модель)

Когда пользователь вызывает `stakeAPY(amount)` на контракте StakingManager:

1. **StakingManager**:
   - Проверяет, что сумма стейкинга больше нуля
   - Оборачивает нативные XFI в WXFI
   - Апрувит WXFI для NativeStakingVault
   - Вызывает функцию `deposit(amount, user)` на контракте NativeStakingVault

2. **NativeStakingVault**:
   - Рассчитывает количество shares (долей) на основе суммы депозита
   - Переводит WXFI от пользователя на контракт
   - Увеличивает количество shares пользователя
   - Генерирует событие StakedAPY

3. **Результат**:
   - XFI пользователя размещены в vault
   - Пользователь получает shares, представляющие его долю в vault

### Детальное описание процесса вывода из vault (APY модель)

Когда пользователь вызывает `withdrawAPY(shares)` на контракте StakingManager:

1. **StakingManager**:
   - Проверяет, что количество shares больше нуля
   - Вызывает функцию `requestRedeem(shares, user)` на контракте NativeStakingVault

2. **NativeStakingVault**:
   - Проверяет, что у пользователя достаточно shares
   - Рассчитывает количество активов (WXFI) на основе shares
   - Уменьшает количество shares пользователя
   - Создает запрос на вывод с уникальным ID
   - Устанавливает время разблокировки = текущее время + период разблокировки
   - Генерирует событие WithdrawalRequestedAPY

3. **Результат**:
   - Создается запрос на вывод с requestId
   - Начинается отсчет периода разблокировки
   - RequestId можно получить из события WithdrawalRequestedAPY

### Детальное описание процесса клейма после вывода из vault (APY модель)

Когда пользователь вызывает `claimWithdrawalAPY(requestId)` на контракте StakingManager:

1. **StakingManager**:
   - Проверяет существование запроса с указанным ID
   - Проверяет, что запрос принадлежит вызывающему пользователю
   - Проверяет, что период разблокировки завершился
   - Вызывает функцию `claimWithdrawal(requestId)` на контракте NativeStakingVault

2. **NativeStakingVault**:
   - Получает информацию о запросе (сумма, пользователь)
   - Отмечает запрос как выполненный
   - Отправляет WXFI пользователю
   - Разворачивает WXFI обратно в XFI
   - Генерирует событие WithdrawalClaimedAPY

3. **Результат**:
   - Пользователь получает свои XFI
   - Запрос отмечается как выполненный

## Проверка статуса и получение информации

### Проверка статуса запроса

```javascript
// Получение информации о запросе
const request = await stakingManager.getRequest(requestId);

// Проверка, можно ли получить средства после анстейкинга
const canClaim = await stakingManager.canClaimUnstake(requestId);
```

### Получение ставок и балансов

```javascript
// Получение текущей APR ставки
const apr = await stakingManager.getAPR();

// Получение текущей APY ставки
const apy = await stakingManager.getAPY();

// Получение баланса пользователя в APR модели
const balance = await stakingManager.userStakeBalanceAPR(userAddress);

// Получение количества shares пользователя в vault
const shares = await stakingManager.userSharesAPY(userAddress);
```

## Отслеживание событий

### Основные события системы

1. **StakedAPR** — Создан новый стейк в APR модели
2. **UnstakedAPR** — Создан запрос на анстейкинг в APR модели
3. **UnstakeClaimedAPR** — Средства успешно выведены после анстейкинга в APR модели
4. **RewardsClaimed** — Получены награды в APR модели
5. **StakedAPY** — Создан новый стейк в Vault (APY модель)
6. **WithdrawalRequestedAPY** — Создан запрос на вывод из Vault
7. **WithdrawalClaimedAPY** — Средства успешно выведены из Vault

Пример подписки на события:

```javascript
// Отслеживание нового стейка
stakingManager.on("StakedAPR", (user, amount, mpxAmount, validator, requestId) => {
  console.log(`Новый стейк: ${user} разместил ${amount} XFI`);
  console.log(`ID запроса: ${requestId}`);
});

// Отслеживание запроса на анстейкинг
stakingManager.on("UnstakedAPR", (user, amount, mpxAmount, validator, requestId) => {
  console.log(`Запрос на анстейкинг: ${user} хочет вывести ${amount} XFI`);
  console.log(`ID запроса: ${requestId}`);
});
```

## Рабочие процессы

### APR модель (прямой стейкинг)

1. Пользователь делает стейкинг XFI через `stakeAPR`
2. Пользователь запрашивает анстейкинг через `unstakeAPR`
3. После периода разблокировки пользователь получает XFI через `claimUnstakeAPR`
4. Пользователь получает награды через `claimRewardsAPR`

### APY модель (Vault)

1. Пользователь делает стейкинг XFI через `stakeAPY` и получает shares
2. Награды автоматически реинвестируются в vault
3. Пользователь запрашивает вывод через `withdrawAPY`
4. После периода разблокировки пользователь получает XFI через `claimWithdrawalAPY`

## Простой пример интеграции (JavaScript)

```javascript
// Инициализация провайдера и контракта
const provider = new ethers.providers.JsonRpcProvider("https://rpc.crossfi.org");
const signer = provider.getSigner(); // или new ethers.Wallet(privateKey, provider);

// Загрузка контракта
const stakingManagerAddress = "0xbda4FCbd54594c482052f8F6212Df471037bD7ef"; // Адрес StakingManager
const stakingManager = new ethers.Contract(
  stakingManagerAddress,
  stakingManagerABI, // Импортировать ABI
  signer
);

// Функция для стейкинга XFI
async function stakeXFI(amount) {
  // Конвертация из обычного формата в wei
  const amountInWei = ethers.utils.parseEther(amount);
  
  // Выполнение стейкинга
  const tx = await stakingManager.stakeAPR(amountInWei, "default", {
    value: amountInWei
  });
  
  // Ожидание подтверждения транзакции
  const receipt = await tx.wait();
  
  // Получение ID запроса из события
  const event = receipt.events.find(e => e.event === "StakedAPR");
  if (event) {
    const requestId = event.args.requestId.toString();
    console.log("Стейкинг успешен! ID запроса:", requestId);
  }
}

// Функция для получения наград
async function claimRewards() {
  const tx = await stakingManager.claimRewardsAPR();
  await tx.wait();
  console.log("Награды успешно получены!");
}
```

## Общие советы для интеграции

1. **Всегда сохраняйте ID запросов** — Они необходимы для последующего получения средств после анстейкинга или вывода из vault.

2. **Отслеживайте события** — События предоставляют важную информацию о статусе операций стейкинга.

3. **Проверяйте возможность вывода средств** — Перед вызовом функций типа `claimUnstakeAPR` используйте `canClaimUnstake` для проверки, завершен ли период разблокировки.

4. **Обрабатывайте ошибки** — Многие операции могут завершиться ошибками, например, при недостаточном балансе или попытке вывести средства до окончания периода разблокировки.

5. **Взаимодействуйте только с NativeStakingManager** — Не обращайтесь напрямую к другим контрактам системы. Все операции должны проходить через NativeStakingManager.

## Заключение

CrossFi Native Staking предоставляет гибкую систему стейкинга с двумя основными моделями — APR и APY. Для интеграции необходимо взаимодействовать только с контрактом NativeStakingManager, который служит единой точкой входа для всех операций.

Пользователь всегда взаимодействует только с NativeStakingManager, который делегирует вызовы соответствующим контрактам, что упрощает интеграцию и обеспечивает стабильный интерфейс, даже если внутренняя логика контрактов изменится в будущем.

При правильной интеграции система обеспечивает надежный и прозрачный механизм для стейкинга XFI токенов и получения наград, позволяя пользователям выбирать наиболее подходящую для них модель доходности. 