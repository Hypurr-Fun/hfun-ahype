# aHYPESeat

A utilization-based seat market contract for gated access control using aHYPE token collateral.

## Overview

SeatMarket is a fee/collateral escrow system that provides gated access through a limited number of "seats." Users lock aHYPE collateral to occupy a seat and accrue fees over time based on system utilization. If a user's debt exceeds their collateral, they become unhealthy and can be liquidated.

## Features

### Seat System

- **Limited Capacity**: Fixed maximum number of seats (`maxSeats`)
- **Collateralized Access**: Users deposit the liquid staking token aHYPE to occupy a seat
- **Enumerable Holders**: Track all seat holders for backend integration

### Utilization-Based Fee Model

Fees scale linearly with utilization:

```
utilization = occupiedSeats / maxSeats
feePerSecond = minFeePerSecond + (maxFeePerSecond - minFeePerSecond) * utilization
```

- Higher utilization = higher fees for all seat holders
- Fees accrue continuously per second
- Global cumulative fee index tracks total fees per seat

### Debt Accounting

- **Cumulative Index**: Global `cumulativeFeePerSeat` grows each second
- **Snapshot System**: Each user tracks their index at join/settlement time
- **User Debt**: `settledDebt + (currentIndex - snapshot)`

### Health System

A position is **healthy** when `collateral >= debt`:

- Healthy positions can withdraw excess collateral
- Unhealthy positions can be liquidated by anyone
- Backend gating: `isActive(user)` returns true only for healthy positions

### Liquidation (Kick)

When `debt > collateral`:
- Anyone can call `kick(user)` to liquidate
- Seat is revoked and position cleared
- Collateral is seized and distributed as fees

### Fee Distribution

Collected fees are split between:
- **Fee Recipient**: Receives `(100% - burnBps%)` of fees
- **Burn**: `burnBps` basis points are burned (deflationary), increasing the value of remaining aHYPE

## Core Functions

### User Actions

| Function | Description |
|----------|-------------|
| `purchaseSeat(amount)` | Deposit collateral and occupy a seat |
| `addCollateral(amount)` | Add more collateral to position |
| `repayFees(amount)` | Repay accrued fees to reduce debt |
| `withdrawCollateral(amount)` | Withdraw excess collateral (must stay healthy) |
| `exit()` | Leave seat, settle debt, receive remaining collateral |

### View Functions

| Function | Description |
|----------|-------------|
| `isActive(user)` | Returns true if user has healthy seat (for API gating) |
| `isHealthy(user)` | Check if position is healthy |
| `debtValueOf(user)` | Get current debt including pending fees |
| `utilizationWad()` | Current utilization (WAD precision) |
| `feePerSecond()` | Current fee rate per seat |
| `feePerDay()` | Current daily fee per seat |
| `feePerYear()` | Current annual fee per seat |
| `minDepositForSeat()` | Minimum deposit required for new seat |
| `getHealthySeats()` | Array of all healthy seat holder addresses |

### Admin Functions

| Function | Description |
|----------|-------------|
| `setParams(...)` | Update maxSeats, fee rates, recipient, burnBps |
| `transferOwnership(newOwner)` | Transfer contract ownership |

## Parameters

| Parameter | Description |
|-----------|-------------|
| `maxSeats` | Maximum number of concurrent seat holders |
| `minFeePerSecond` | Minimum fee rate (at 0% utilization) |
| `maxFeePerSecond` | Maximum fee rate (at 100% utilization) |
| `feeRecipient` | Address receiving non-burned fees |
| `burnBps` | Basis points of fees to burn (0-10000) |

## Security

- Reentrancy guard on all state-changing functions
- Checks-effects-interactions pattern
- Assumes aHYPE is standard ERC20 (no transfer fees/rebasing)

## Build & Test

```shell
forge build
forge test
```

## License

MIT
