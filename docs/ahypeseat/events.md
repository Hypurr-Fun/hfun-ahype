# aHYPESeat Events Reference

Complete event reference for the SeatMarket contract.

## Fee Accrual Events

### Accrued

Emitted when fees are accrued to the cumulative index.

```solidity
event Accrued(
    uint256 dt,
    uint256 feePerSecond,
    uint256 totalFeeAccrued,
    uint256 newCumulativeFee
);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `dt` | `uint256` | No | Time elapsed since last accrual (seconds) |
| `feePerSecond` | `uint256` | No | Fee rate during this period (WAD) |
| `totalFeeAccrued` | `uint256` | No | Total fees accrued this period |
| `newCumulativeFee` | `uint256` | No | New cumulative fee index |

---

## Seat Lifecycle Events

### SeatPurchased

Emitted when a user purchases a seat.

```solidity
event SeatPurchased(address indexed user, uint256 deposit);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `user` | `address` | Yes | Address that purchased the seat |
| `deposit` | `uint256` | No | Amount of aHYPE deposited |

---

### SeatKicked

Emitted when an unhealthy position is liquidated.

```solidity
event SeatKicked(
    address indexed user,
    address indexed kicker,
    uint256 collateralSeized,
    uint256 debtValue
);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `user` | `address` | Yes | Address that was liquidated |
| `kicker` | `address` | Yes | Address that performed liquidation |
| `collateralSeized` | `uint256` | No | Amount of collateral seized |
| `debtValue` | `uint256` | No | Debt value at liquidation |

---

## Collateral Events

### CollateralAdded

Emitted when a user adds collateral to their position.

```solidity
event CollateralAdded(address indexed user, uint256 amount);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `user` | `address` | Yes | Address adding collateral |
| `amount` | `uint256` | No | Amount of aHYPE added |

---

### CollateralWithdrawn

Emitted when a user withdraws excess collateral.

```solidity
event CollateralWithdrawn(address indexed user, uint256 amount);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `user` | `address` | Yes | Address withdrawing collateral |
| `amount` | `uint256` | No | Amount of aHYPE withdrawn |

---

## Fee Events

### FeesRepaid

Emitted when a user repays accrued fees.

```solidity
event FeesRepaid(address indexed user, uint256 amount);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `user` | `address` | Yes | Address repaying fees |
| `amount` | `uint256` | No | Amount of fees repaid |

---

### FeeDistributed

Emitted when fees are distributed (to recipient and burn).

```solidity
event FeeDistributed(uint256 toRecipient, uint256 burned);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `toRecipient` | `uint256` | No | Amount sent to fee recipient |
| `burned` | `uint256` | No | Amount burned |

---

## Admin Events

### ParamsUpdated

Emitted when market parameters are updated.

```solidity
event ParamsUpdated(
    uint256 maxSeats,
    uint256 minFeePerSecond,
    uint256 maxFeePerSecond,
    address feeRecipient,
    uint256 burnBps
);
```

| Parameter | Type | Indexed | Description |
|-----------|------|---------|-------------|
| `maxSeats` | `uint256` | No | New maximum seats |
| `minFeePerSecond` | `uint256` | No | New minimum fee rate |
| `maxFeePerSecond` | `uint256` | No | New maximum fee rate |
| `feeRecipient` | `address` | No | New fee recipient address |
| `burnBps` | `uint256` | No | New burn rate in basis points |

---

## Event Flow Examples

### Complete Seat Purchase Flow

```
1. User calls purchaseSeat(1000e8)
   └── SeatPurchased(user, 1000e8)

2. Time passes, fees accrue
   └── Accrued(86400, feeRate, totalFee, newIndex)  // on next interaction
```

### Fee Repayment Flow

```
1. User checks debt
   └── debtValueOf(user) returns 50e8

2. User calls repayFees(50e8)
   └── FeesRepaid(user, 50e8)
   └── FeeDistributed(45e8, 5e8)  // assuming 10% burn
```

### Liquidation Flow

```
1. Position becomes unhealthy (debt > collateral)

2. Liquidator calls kick(user)
   └── SeatKicked(user, liquidator, collateral, debt)
   └── FeeDistributed(collateral * 0.9, collateral * 0.1)
```

### Voluntary Exit Flow

```
1. User calls exit()
   └── FeeDistributed(debt * 0.9, debt * 0.1)
   └── User receives (collateral - debt) aHYPE
```

---

## Monitoring Recommendations

### Key Events for Integrators

| Use Case | Events to Monitor |
|----------|-------------------|
| Track seat changes | `SeatPurchased`, `SeatKicked`, exit (no event) |
| Monitor fees | `Accrued`, `FeesRepaid`, `FeeDistributed` |
| Track collateral | `CollateralAdded`, `CollateralWithdrawn` |
| Liquidation bots | `SeatKicked` (for confirmation) |
| Parameter changes | `ParamsUpdated` |

### Liquidation Bot Integration

To build a liquidation bot:

1. Monitor `SeatPurchased` to track new positions
2. Periodically call `isHealthy(user)` for all seat holders
3. When unhealthy found, call `kick(user)`
4. Listen for `SeatKicked` to confirm liquidation

### Event Indexing

All address parameters with `indexed` modifier can be filtered efficiently:
- `user` in seat and collateral events
- `kicker` in liquidation events

### Fee Tracking

To calculate total fees collected:
1. Sum all `FeeDistributed.toRecipient` events
2. Sum all `FeeDistributed.burned` events for burn statistics

### Utilization Tracking

Monitor `SeatPurchased` and `SeatKicked` events to track:
- `occupiedSeats` changes
- Utilization rate changes
- Fee rate implications
