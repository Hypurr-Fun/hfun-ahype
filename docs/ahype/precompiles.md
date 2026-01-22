# HyperCore Precompiles

The AlphaHYPEManager integrates with Hyperliquid's core through precompiled contracts. These precompiles provide read and write access to the Hyperliquid state.

## Overview

| Library | Purpose | Precompile Range |
|---------|---------|------------------|
| L1Read | Query Hyperliquid state | `0x0800` - `0x080F` |
| L1Write | Mutate Hyperliquid state | `0x3333...3333` |

## L1Read - Read Operations

### Precompile Addresses

```solidity
address constant DELEGATOR_SUMMARY = 0x0000000000000000000000000000000000000800;
address constant SPOT_BALANCE = 0x0000000000000000000000000000000000000801;
address constant POSITION = 0x0000000000000000000000000000000000000802;
// ... additional addresses
```

### delegatorSummary

Get staking delegation summary for an address.

```solidity
function delegatorSummary(address user) internal view returns (DelegatorSummary memory)
```

**Returns:**

```solidity
struct DelegatorSummary {
    uint64 delegated;           // Total delegated stake
    uint64 undelegated;         // Stake being undelegated
    uint64 totalPendingWithdrawals;  // Pending withdrawal amount
    uint64 nDelegations;        // Number of active delegations
}
```

**Used for:** Calculating underlying HYPE backing from staked amounts.

---

### spotBalance

Get spot balance for a token.

```solidity
function spotBalance(address user, uint64 token) internal view returns (SpotBalance memory)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `user` | `address` | Address to query |
| `token` | `uint64` | Token index on Hyperliquid Spot |

**Returns:**

```solidity
struct SpotBalance {
    uint64 total;    // Total balance
    uint64 hold;     // Amount on hold
}
```

**Used for:** Calculating underlying HYPE in Spot holdings.

---

### delegations

Get all delegations for an address.

```solidity
function delegations(address user) internal view returns (Delegation[] memory)
```

**Returns:**

```solidity
struct Delegation {
    address validator;
    uint64 amount;
    uint64 lockedUntil;  // Unlock timestamp
}
```

---

### Additional Read Functions

| Function | Description |
|----------|-------------|
| `position(address, uint16)` | Get perpetual position |
| `tokenSupply(uint32)` | Get token supply info |
| `tokenInfo(uint32)` | Get token metadata |
| `markPrice(uint16)` | Get perpetual mark price |
| `oraclePrice(uint16)` | Get oracle price |

---

## L1Write - Write Operations

### CoreWriter Interface

All write operations go through the CoreWriter precompile:

```solidity
address constant CORE_WRITER = 0x3333333333333333333333333333333333333333;

interface CoreWriter {
    function write(bytes memory action) external;
}
```

### tokenDelegate

Delegate or undelegate HYPE to a validator.

```solidity
function tokenDelegate(address validator, uint256 amount, bool isUndelegate) internal
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `validator` | `address` | Validator address |
| `amount` | `uint256` | Amount to delegate/undelegate |
| `isUndelegate` | `bool` | `true` to undelegate, `false` to delegate |

**Action Type:** `TokenDelegate`

---

### stakingDeposit

Deposit HYPE to staking.

```solidity
function stakingDeposit(uint64 amount) internal
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `amount` | `uint64` | Amount to deposit (8 decimals) |

**Action Type:** `CDeposit`

---

### stakingWithdraw

Withdraw HYPE from staking.

```solidity
function stakingWithdraw(uint64 amount) internal
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `amount` | `uint64` | Amount to withdraw (8 decimals) |

**Action Type:** `CWithdraw`

---

### spotSend

Bridge HYPE between Spot and EVM.

```solidity
function spotSend(address destination, uint256 token, uint256 amount) internal
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `destination` | `address` | Recipient address |
| `token` | `uint256` | Token index |
| `amount` | `uint256` | Amount to send |

**Action Type:** `SpotSend`

---

## System Addresses

```solidity
// HYPE system bridge address - transfers to this address move HYPE between core and EVM
address constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;
```

## Usage in AlphaHYPEManager

### Reading State

```solidity
// Get delegation info
L1Read.DelegatorSummary memory summary = L1Read.delegatorSummary(address(this));
uint256 stakedHype = summary.delegated + summary.undelegated + summary.totalPendingWithdrawals;

// Get spot balance
L1Read.SpotBalance memory spot = L1Read.spotBalance(address(this), hypeTokenIndex);
uint256 spotHype = spot.total;
```

### Writing State

```solidity
// Delegate to validator
L1Write.tokenDelegate(validator, amount, false);

// Undelegate from validator
L1Write.tokenDelegate(validator, amount, true);

// Deposit to staking pool
L1Write.stakingDeposit(uint64(amount));

// Withdraw from staking pool
L1Write.stakingWithdraw(uint64(amount));

// Bridge from Spot to EVM
L1Write.spotSend(address(this), hypeTokenIndex, amount);
```

## Precision Handling

| Context | Decimals | Notes |
|---------|----------|-------|
| EVM native HYPE | 18 | Standard wei |
| L1Read amounts | 8 | Hyperliquid standard |
| L1Write amounts | 8 | Must convert from wei |
| αHYPE token | 8 | Matches Hyperliquid |

**Conversion constant:**

```solidity
uint256 constant SCALE_18_TO_8 = 1e10;

// Wei to 8 decimals
uint256 scaled = weiAmount / SCALE_18_TO_8;

// 8 decimals to wei
uint256 wei = scaledAmount * SCALE_18_TO_8;
```
