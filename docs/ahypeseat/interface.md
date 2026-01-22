# aHYPESeat Contract Interface

Complete API reference for the SeatMarket contract.

## Constructor

```solidity
constructor(
    address hypeToken,
    uint256 _maxSeats,
    uint256 _minFeePerSecond,
    uint256 _maxFeePerSecond,
    address _feeRecipient,
    uint256 _burnBps
)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `hypeToken` | `address` | aHYPE token contract address |
| `_maxSeats` | `uint256` | Maximum number of seats |
| `_minFeePerSecond` | `uint256` | Minimum fee rate (WAD per second) |
| `_maxFeePerSecond` | `uint256` | Maximum fee rate (WAD per second) |
| `_feeRecipient` | `address` | Address to receive fees |
| `_burnBps` | `uint256` | Basis points to burn (0-10000) |

---

## User Functions

### purchaseSeat

Deposit collateral and occupy a seat.

```solidity
function purchaseSeat(uint256 deposit) external nonReentrant
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `deposit` | `uint256` | Amount of aHYPE to deposit |

**Requirements:**
- Caller must not already have a seat
- `deposit >= minDepositForSeat()`
- `occupiedSeats < maxSeats`
- Caller must have approved contract for `deposit` amount

**Behavior:**
- Transfers aHYPE from caller to contract
- Creates new position with `hasSeat = true`
- Snapshots current `cumulativeFeePerSeat`
- Adds caller to `seatHolders` array

**Emits:** `SeatPurchased(address indexed user, uint256 deposit)`

---

### addCollateral

Add more collateral to an existing position.

```solidity
function addCollateral(uint256 amount) external nonReentrant
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `amount` | `uint256` | Amount of aHYPE to add |

**Requirements:**
- Caller must have a seat
- Caller must have approved contract for `amount`

**Behavior:**
- Transfers aHYPE from caller to contract
- Increases `position.collateral` by `amount`

**Emits:** `CollateralAdded(address indexed user, uint256 amount)`

---

### repayFees

Repay accrued fees to reduce debt.

```solidity
function repayFees(uint256 amount) external nonReentrant
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `amount` | `uint256` | Amount to repay |

**Requirements:**
- Caller must have a seat
- `amount <= debtValueOf(caller)`
- Caller must have approved contract for `amount`

**Behavior:**
- Accrues fees to current timestamp
- Transfers aHYPE from caller to contract
- Reduces `settledDebt` by repayment
- Distributes repayment as fees (burn + recipient)
- Updates fee index snapshot

**Emits:** `FeesRepaid(address indexed user, uint256 amount)`

---

### withdrawCollateral

Withdraw excess collateral (must remain healthy).

```solidity
function withdrawCollateral(uint256 amount) external nonReentrant
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `amount` | `uint256` | Amount of aHYPE to withdraw |

**Requirements:**
- Caller must have a seat
- Position must remain healthy after withdrawal: `collateral - amount >= debt`

**Behavior:**
- Accrues fees to current timestamp
- Settles current debt
- Reduces collateral by `amount`
- Transfers aHYPE to caller

**Emits:** `CollateralWithdrawn(address indexed user, uint256 amount)`

---

### exit

Voluntarily exit, settle debt, and receive remaining collateral.

```solidity
function exit() external nonReentrant
```

**Requirements:**
- Caller must have a seat

**Behavior:**
- Accrues fees to current timestamp
- Calculates final debt
- If `debt <= collateral`:
  - Distributes debt as fees
  - Returns `collateral - debt` to user
- If `debt > collateral`:
  - Distributes all collateral as fees
  - User receives nothing
- Removes seat and clears position
- Removes from `seatHolders` array

**Emits:** `FeeDistributed(uint256 toRecipient, uint256 burned)`

---

### kick

Liquidate an unhealthy position.

```solidity
function kick(address user) external nonReentrant
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `user` | `address` | Address to liquidate |

**Requirements:**
- Target must have a seat
- Target must be unhealthy: `debt > collateral`

**Behavior:**
- Accrues fees to current timestamp
- Seizes all collateral
- Distributes collateral as fees (burn + recipient)
- Removes seat and clears position
- Removes from `seatHolders` array

**Emits:** `SeatKicked(address indexed user, address indexed kicker, uint256 collateralSeized, uint256 debtValue)`

---

## View Functions

### isActive

Check if user has a healthy seat (for API gating).

```solidity
function isActive(address user) external view returns (bool)
```

**Returns:** `true` if user has a seat AND `collateral >= debt`

**Use Case:** Backend access control systems should call this to verify access.

---

### isHealthy

Check if a position is healthy.

```solidity
function isHealthy(address user) public view returns (bool)
```

**Returns:** `true` if `collateral >= debt`

---

### debtValueOf

Get current debt including pending (unaccrued) fees.

```solidity
function debtValueOf(address user) public view returns (uint256)
```

**Returns:** `settledDebt + (cumulativeFeePerSeatView() - feeIndexSnapshot)`

---

### utilizationWad

Get current utilization rate.

```solidity
function utilizationWad() public view returns (uint256)
```

**Returns:** `(occupiedSeats * WAD) / maxSeats`

---

### feePerSecond

Get current fee rate per second.

```solidity
function feePerSecond() public view returns (uint256)
```

**Returns:** `minFeePerSecond + (maxFeePerSecond - minFeePerSecond) * utilization / WAD`

---

### feePerDay

Get current daily fee rate.

```solidity
function feePerDay() external view returns (uint256)
```

**Returns:** `feePerSecond() * 86400`

---

### feePerYear

Get current annual fee rate.

```solidity
function feePerYear() external view returns (uint256)
```

**Returns:** `feePerSecond() * 31536000`

---

### minDepositForSeat

Get minimum deposit required for a new seat.

```solidity
function minDepositForSeat() public view returns (uint256)
```

**Returns:** Minimum collateral needed (typically 1 day of maximum fees)

---

### getHealthySeats

Get array of all healthy seat holder addresses.

```solidity
function getHealthySeats() external view returns (address[] memory)
```

**Returns:** Array of addresses with `isActive(addr) == true`

**Note:** May be gas-intensive for large seat counts. Use for off-chain queries.

---

### cumulativeFeePerSeatView

Get cumulative fee index including pending accruals.

```solidity
function cumulativeFeePerSeatView() public view returns (uint256)
```

**Returns:** `cumulativeFeePerSeat + (feePerSecond() * timeSinceLastAccrual)`

---

### positions

Get position data for a user.

```solidity
function positions(address user) external view returns (Position memory)
```

**Returns:**

```solidity
struct Position {
    bool hasSeat;
    uint256 collateral;
    uint256 settledDebt;
    uint256 feeIndexSnapshot;
}
```

---

## Admin Functions

### setParams

Update market parameters.

```solidity
function setParams(
    uint256 _maxSeats,
    uint256 _minFeePerSecond,
    uint256 _maxFeePerSecond,
    address _feeRecipient,
    uint256 _burnBps
) external onlyOwner
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `_maxSeats` | `uint256` | New maximum seats |
| `_minFeePerSecond` | `uint256` | New minimum fee rate |
| `_maxFeePerSecond` | `uint256` | New maximum fee rate |
| `_feeRecipient` | `address` | New fee recipient |
| `_burnBps` | `uint256` | New burn rate (0-10000 BPS) |

**Requirements:**
- `_maxSeats >= occupiedSeats`
- `_minFeePerSecond <= _maxFeePerSecond`
- `_burnBps <= 10000`
- `_feeRecipient != address(0)`

**Emits:** `ParamsUpdated(uint256 maxSeats, uint256 minFeePerSecond, uint256 maxFeePerSecond, address feeRecipient, uint256 burnBps)`

---

### transferOwnership

Transfer contract ownership.

```solidity
function transferOwnership(address newOwner) external onlyOwner
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `newOwner` | `address` | New owner address |

**Requirements:**
- `newOwner != address(0)`

---

## Error Conditions

| Error | Condition |
|-------|-----------|
| `AlreadyHasSeat` | User already has a seat |
| `NoSeat` | User does not have a seat |
| `MarketFull` | All seats are occupied |
| `InsufficientDeposit` | Deposit below minimum |
| `WouldBecomeUnhealthy` | Action would make position unhealthy |
| `CannotKickHealthy` | Target position is healthy |
| `RepaymentExceedsDebt` | Repay amount exceeds current debt |
| `InvalidParams` | Invalid admin parameters |
