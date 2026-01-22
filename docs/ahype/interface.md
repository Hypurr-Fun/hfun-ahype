# aHYPE Contract Interface

Complete API reference for the AlphaHYPEManager contract.

## Initialization

### initialize

Initializes the upgradeable contract. Must be called immediately after deployment.

```solidity
function initialize(address validator, uint64 hypeTokenIndex) external initializer
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `validator` | `address` | Target validator address for HYPE delegation |
| `hypeTokenIndex` | `uint64` | HYPE token index on Hyperliquid Spot |

**Access:** Can only be called once during proxy deployment.

---

## User Functions

### receive (Deposit)

Deposit native HYPE to queue for αHYPE minting.

```solidity
receive() external payable
```

**Requirements:**
- `msg.value >= minDepositAmount`
- `msg.value` must be a multiple of `10^10` wei (8-decimal alignment)
- Deposit queue length < 100
- If `maxSupply > 0`, minting must not exceed cap

**Emits:** `DepositQueued(address indexed depositor, uint256 amount)`

---

### withdraw

Request withdrawal of αHYPE tokens for underlying HYPE.

```solidity
function withdraw(uint256 amount) external nonReentrant
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `amount` | `uint256` | Amount of αHYPE to withdraw |

**Requirements:**
- Caller must have sufficient αHYPE balance
- Withdrawal queue length < 100

**Behavior:**
- Burns αHYPE immediately
- Locks current exchange rate snapshot for slashing protection
- Queues `WithdrawalRequest` for processing

**Emits:** `WithdrawalQueued(address indexed withdrawer, uint256 wrappedAmount)`

---

### claimWithdrawal

Claim processed HYPE after withdrawal has been settled.

```solidity
function claimWithdrawal() external nonReentrant
```

**Requirements:**
- Caller must have non-zero `owedUnderlyingAmounts[msg.sender]`

**Behavior:**
- Transfers owed HYPE to caller (scaled back to 18 decimals)
- Zeros owed amount before transfer (reentrancy protection)

**Emits:** `WithdrawalClaimed(address indexed withdrawer, uint256 amount)`

---

## Processing Functions

### processQueues

Process pending deposits and withdrawals. Can be called once per block.

```solidity
function processQueues() external nonReentrant
```

**Access:**
- If `processor` is set: only callable by processor
- If `processor` is zero address: callable by anyone

**Requirements:**
- `block.number > lastProcessedBlock`

**Behavior:**
1. Validates solvency against EVM holdings
2. Reads HyperCore state (delegator summary, spot balance)
3. Calculates deposit/withdrawal prices
4. Processes deposit queue (mints αHYPE minus fee)
5. Processes withdrawal queue when liquidity permits
6. Balances liquidity across EVM/Spot/Staking

**Emits:** Multiple events depending on operations performed

---

## Admin Functions

### setMaxSupply

Set the maximum αHYPE supply cap.

```solidity
function setMaxSupply(uint64 _maxSupply) external onlyOwner
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `_maxSupply` | `uint64` | Maximum supply cap (0 = no cap) |

**Access:** Owner only

---

### setMinDepositAmount

Set the minimum deposit amount.

```solidity
function setMinDepositAmount(uint256 _minDepositAmount) external onlyOwner
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `_minDepositAmount` | `uint256` | Minimum deposit in wei |

**Access:** Owner only

---

### setProcessor

Set the designated processor address.

```solidity
function setProcessor(address _processor) external onlyOwner
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `_processor` | `address` | Processor address (zero = permissionless) |

**Access:** Owner only

---

### collectFees

Withdraw accumulated protocol fees.

```solidity
function collectFees() external onlyOwner nonReentrant
```

**Behavior:**
- Transfers accumulated `feeAmount` to owner
- Zeros `feeAmount` before transfer

**Access:** Owner only

---

## View Functions

### getERC20Supply

Get total αHYPE supply including queued withdrawals.

```solidity
function getERC20Supply() public view returns (uint256)
```

**Returns:** `totalSupply() + withdrawalAmount`

---

### getUnderlyingSupply

Get total HYPE backing available for price calculation.

```solidity
function getUnderlyingSupply() public view returns (uint256)
```

**Returns:** Combined HYPE from:
- EVM balance (scaled to 8 decimals)
- Delegated stake
- Undelegated stake
- Pending withdrawals from staking
- Spot holdings

Minus:
- `pendingDepositAmount`
- `withdrawalAmount`
- `feeAmount`
- `owedUnderlyingAmount`

---

### decimals

Get token decimals.

```solidity
function decimals() public pure override returns (uint8)
```

**Returns:** `8`

---

### pendingDepositQueueLength

Get number of pending deposits.

```solidity
function pendingDepositQueueLength() external view returns (uint256)
```

**Returns:** Length of `depositQueue`

---

### pendingWithdrawalQueueLength

Get number of pending withdrawals.

```solidity
function pendingWithdrawalQueueLength() external view returns (uint256)
```

**Returns:** Length of `pendingWithdrawalQueue`

---

## Inherited ERC20 Functions

Standard ERC20 functions inherited from OpenZeppelin:

| Function | Description |
|----------|-------------|
| `name()` | Returns "Alpha HYPE" |
| `symbol()` | Returns "αHYPE" |
| `totalSupply()` | Total minted αHYPE |
| `balanceOf(address)` | αHYPE balance of address |
| `transfer(address, uint256)` | Transfer αHYPE |
| `approve(address, uint256)` | Approve spender |
| `transferFrom(address, address, uint256)` | Transfer from approved |
| `allowance(address, address)` | Check allowance |
| `burn(uint256)` | Burn own αHYPE |
| `burnFrom(address, uint256)` | Burn from approved |

---

## Error Conditions

| Error | Condition |
|-------|-----------|
| `InvalidDepositAmount` | Deposit below minimum or not aligned |
| `QueueFull` | Queue exceeds 100 entries |
| `MaxSupplyExceeded` | Minting would exceed supply cap |
| `InsufficientBalance` | Caller lacks αHYPE for withdrawal |
| `NothingToClaim` | No owed HYPE to claim |
| `AlreadyProcessed` | Queue already processed this block |
| `UnauthorizedProcessor` | Non-processor called processQueues |
