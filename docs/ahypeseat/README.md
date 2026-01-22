# aHYPESeat - Utilization-Based Seat Market

SeatMarket is a fee/collateral escrow system that provides gated access through a limited number of "seats." Users lock aHYPE collateral to occupy a seat and accrue fees over time based on system utilization. Unhealthy positions can be liquidated by anyone.

## Key Features

- **Limited Capacity**: Fixed maximum number of seats (`maxSeats`)
- **Collateralized Access**: Users deposit aHYPE to occupy a seat
- **Utilization-Based Fees**: Fee rate scales with seat occupancy
- **Liquidation System**: Unhealthy positions can be kicked
- **Deflationary Burns**: Portion of fees burned to increase αHYPE value
- **Enumerable Holders**: Track all seat holders for backend integration

## Use Cases

- API access gating for premium services
- Rate-limited access to compute resources
- Membership systems with dynamic pricing
- Collateralized subscription services

## Fee Model

Fees scale linearly with utilization:

```
utilization = occupiedSeats / maxSeats

feePerSecond = minFeePerSecond + (maxFeePerSecond - minFeePerSecond) × utilization
```

### Example Fee Calculation

| Utilization | Min Fee (APR) | Max Fee (APR) | Effective Fee |
|-------------|---------------|---------------|---------------|
| 0% | 10% | 100% | 10% |
| 50% | 10% | 100% | 55% |
| 100% | 10% | 100% | 100% |

Fees accrue continuously per second and are tracked via a global cumulative index.

## Debt Accounting

### Global Index

```
cumulativeFeePerSeat += feePerSecond × timeDelta
```

The global index grows every second based on current utilization.

### Per-User Tracking

Each user stores a snapshot of the cumulative index when they join or settle:

```
userDebt = settledDebt + (currentIndex - userSnapshot)
```

This allows O(1) debt calculation without iterating over time periods.

## Health System

A position is **healthy** when:

```
collateral >= debt
```

| Condition | Status | Actions Available |
|-----------|--------|-------------------|
| `collateral >= debt` | Healthy | Withdraw excess, add collateral, repay |
| `collateral < debt` | Unhealthy | Can be liquidated by anyone |

### Access Gating

Backend systems use `isActive(user)` for access control:
- Returns `true` if user has a seat AND position is healthy
- Returns `false` otherwise

## Liquidation (Kick)

When a position becomes unhealthy (`debt > collateral`), anyone can liquidate:

```
kick(unhealthyUser)
```

**Liquidation Process:**
1. Seat is revoked and removed from holder list
2. Position cleared (collateral, debt, snapshot reset)
3. Collateral seized and distributed as fees

**Fee Distribution:**
- `(100% - burnBps%)` sent to `feeRecipient`
- `burnBps%` burned (removed from circulation)

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `maxSeats` | `uint256` | Maximum concurrent seat holders |
| `minFeePerSecond` | `uint256` | Minimum fee rate (WAD, 1e18 = 100%) |
| `maxFeePerSecond` | `uint256` | Maximum fee rate at 100% utilization |
| `feeRecipient` | `address` | Address receiving non-burned fees |
| `burnBps` | `uint256` | Basis points of fees to burn (0-10000) |

## Storage Layout

### Position Struct

```solidity
struct Position {
    bool hasSeat;               // Whether user holds a seat
    uint256 collateral;         // aHYPE locked as collateral
    uint256 settledDebt;        // Crystallized debt amount
    uint256 feeIndexSnapshot;   // cumulativeFeePerSeat at join/settle
}
```

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `HYPE` | `IERC20` | aHYPE token contract (immutable) |
| `maxSeats` | `uint256` | Maximum seats available |
| `occupiedSeats` | `uint256` | Current number of occupied seats |
| `cumulativeFeePerSeat` | `uint256` | Global fee accumulator (WAD) |
| `lastAccrualTime` | `uint256` | Timestamp of last fee accrual |
| `positions` | `mapping(address => Position)` | User positions |
| `seatHolders` | `address[]` | Array of all seat holder addresses |

## Constants

```solidity
uint256 constant WAD = 1e18;  // High-precision decimal (18 decimals)
```

## User Lifecycle

### Joining

```
1. User calls purchaseSeat(depositAmount)
   └── Must have >= minDepositForSeat() aHYPE

2. Transfer aHYPE to contract
   └── Sets collateral = depositAmount

3. Create seat
   └── hasSeat = true
   └── feeIndexSnapshot = cumulativeFeePerSeat
   └── Add to seatHolders array
```

### Maintaining

```
While holding seat:
├── addCollateral(amount)     // Increase safety buffer
├── repayFees(amount)         // Reduce debt
├── withdrawCollateral(amount) // Remove excess (must stay healthy)
└── Monitor: debtValueOf(user) // Check current debt
```

### Exiting

```
Voluntary exit:
└── User calls exit()
    ├── Settle debt from collateral
    ├── Return remaining collateral
    └── Remove from seatHolders

Forced exit (liquidation):
└── Anyone calls kick(user) when unhealthy
    ├── Seize all collateral
    ├── Distribute as fees (burn + recipient)
    └── Remove from seatHolders
```

## Integration Guide

### Checking Access

```solidity
// For backend gating
if (seatMarket.isActive(user)) {
    // Grant access
} else {
    // Deny access
}
```

### Getting All Active Seats

```solidity
// Returns array of healthy seat holders
address[] memory activeUsers = seatMarket.getHealthySeats();
```

### Monitoring Debt

```solidity
// Get current debt including pending fees
uint256 debt = seatMarket.debtValueOf(user);

// Get position details
Position memory pos = seatMarket.positions(user);
uint256 collateral = pos.collateral;

// Health check
bool healthy = collateral >= debt;
```
