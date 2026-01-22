# aHYPE Events Reference

Complete event reference for the AlphaHYPEManager contract.

## Deposit Events

### DepositQueued

Emitted when a user deposits HYPE to the queue.

```solidity
event DepositQueued(address indexed depositor, uint256 amount);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `depositor` | `address` | Yes | Address that deposited HYPE |
| `amount` | `uint256` | No | Amount of HYPE deposited (wei) |

---

### DepositProcessed

Emitted when a queued deposit is processed and αHYPE is minted.

```solidity
event DepositProcessed(address indexed depositor, uint256 amount, uint256 wrappedAmount);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `depositor` | `address` | Yes | Address receiving αHYPE |
| `amount` | `uint256` | No | HYPE amount deposited |
| `wrappedAmount` | `uint256` | No | αHYPE minted (after fee) |

---

## Withdrawal Events

### WithdrawalQueued

Emitted when a user requests a withdrawal.

```solidity
event WithdrawalQueued(address indexed withdrawer, uint256 wrappedAmount);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `withdrawer` | `address` | Yes | Address requesting withdrawal |
| `wrappedAmount` | `uint256` | No | αHYPE amount to withdraw |

---

### WithdrawalProcessed

Emitted when a withdrawal request is settled.

```solidity
event WithdrawalProcessed(address indexed withdrawer, uint256 amount, uint256 wrappedAmount);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `withdrawer` | `address` | Yes | Address with processed withdrawal |
| `amount` | `uint256` | No | HYPE amount owed |
| `wrappedAmount` | `uint256` | No | αHYPE amount burned |

---

### WithdrawalClaimed

Emitted when a user claims their processed HYPE.

```solidity
event WithdrawalClaimed(address indexed withdrawer, uint256 amount);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `withdrawer` | `address` | Yes | Address claiming HYPE |
| `amount` | `uint256` | No | HYPE amount claimed (wei) |

---

## Bridging Events

### EVMSend

Emitted when HYPE is sent within EVM.

```solidity
event EVMSend(uint256 amount, address to);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `amount` | `uint256` | No | Amount sent |
| `to` | `address` | No | Recipient address |

---

### SpotSend

Emitted when HYPE is bridged to/from Spot.

```solidity
event SpotSend(uint256 amount, address to);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `amount` | `uint256` | No | Amount bridged |
| `to` | `address` | No | Recipient address |

---

## Staking Events

### StakingDeposit

Emitted when HYPE is deposited to staking.

```solidity
event StakingDeposit(uint256 amount);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `amount` | `uint256` | No | Amount deposited to staking |

---

### StakingWithdraw

Emitted when HYPE is withdrawn from staking.

```solidity
event StakingWithdraw(uint256 amount);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `amount` | `uint256` | No | Amount withdrawn from staking |

---

### TokenDelegate

Emitted when HYPE is delegated or undelegated to a validator.

```solidity
event TokenDelegate(address indexed validator, uint256 amount, bool isUndelegate);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `validator` | `address` | Yes | Validator address |
| `amount` | `uint256` | No | Amount delegated/undelegated |
| `isUndelegate` | `bool` | No | `true` if undelegating, `false` if delegating |

---

## Event Flow Examples

### Complete Deposit Flow

```
1. User sends HYPE
   └── DepositQueued(user, 1000e18)

2. Processor calls processQueues()
   └── DepositProcessed(user, 1000e18, 999e8)  // minus 0.1% fee
   └── TokenDelegate(validator, 1000e8, false)  // delegate to staking
```

### Complete Withdrawal Flow

```
1. User calls withdraw(100e8)
   └── WithdrawalQueued(user, 100e8)

2. Processor calls processQueues()
   └── StakingWithdraw(100e8)  // if needed
   └── SpotSend(100e8, contract)  // bridge if needed
   └── WithdrawalProcessed(user, 99.9e8, 100e8)  // minus 0.1% fee

3. User calls claimWithdrawal()
   └── WithdrawalClaimed(user, 99.9e18)  // scaled to 18 decimals
```

---

## Monitoring Recommendations

### Key Events for Integrators

| Use Case | Events to Monitor |
|----------|-------------------|
| Track deposits | `DepositQueued`, `DepositProcessed` |
| Track withdrawals | `WithdrawalQueued`, `WithdrawalProcessed`, `WithdrawalClaimed` |
| Monitor TVL changes | `StakingDeposit`, `StakingWithdraw`, `TokenDelegate` |
| Detect bridging activity | `EVMSend`, `SpotSend` |

### Event Indexing

All address parameters with `indexed` modifier can be filtered efficiently:
- `depositor` in deposit events
- `withdrawer` in withdrawal events
- `validator` in delegation events
