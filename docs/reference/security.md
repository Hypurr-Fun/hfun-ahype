# Security Model

Security considerations and safety features of the aHYPE protocol.

## aHYPE Security Features

### Queue Caps

Hard limit of 100 entries per queue prevents unbounded loops and DoS attacks:

```solidity
require(depositQueue.length < 100, "Queue full");
require(pendingWithdrawalQueue.length < 100, "Queue full");
```

**Rationale:** Prevents gas exhaustion attacks where an attacker could fill queues with small deposits to make `processQueues()` exceed block gas limits.

### Pull-Based Withdrawals

Withdrawals use a two-step claim pattern:

1. `withdraw()` - Burns αHYPE, queues request, records amount owed
2. `claimWithdrawal()` - User pulls their HYPE

```solidity
mapping(address => uint256) owedUnderlyingAmounts;
```

**Rationale:**
- Eliminates reentrancy vectors during withdrawal processing
- Allows batch processing without external calls per user
- Users can claim at their convenience

### Slashing Protection

Withdrawal requests lock the exchange rate at queue time:

```solidity
struct WithdrawalRequest {
    address withdrawer;
    uint256 amount;
    uint256 pricePerTokenX18;  // Snapshot
}
```

Processing uses the minimum of locked and current price:

```solidity
uint256 effectivePrice = min(request.pricePerTokenX18, currentPrice);
```

**Rationale:** If validator is slashed between queue and claim, users don't receive more than the pool can support.

### One-Per-Block Processing

```solidity
require(block.number > lastProcessedBlock, "Already processed");
lastProcessedBlock = block.number;
```

**Rationale:** Prevents multiple processing calls in the same block that could exploit price calculation timing.

### Precision Handling

- All internal accounting uses 8 decimals (matching Hyperliquid)
- Deposits must be multiples of `10^10` wei to avoid dust
- `Math.mulDiv` used for high-precision division without overflow

```solidity
uint256 constant SCALE_18_TO_8 = 1e10;
require(amount % SCALE_18_TO_8 == 0, "Invalid amount");
```

### Reentrancy Protection

All state-changing functions use `nonReentrant` modifier:

```solidity
function withdraw(uint256 amount) external nonReentrant { ... }
function claimWithdrawal() external nonReentrant { ... }
function processQueues() external nonReentrant { ... }
function collectFees() external onlyOwner nonReentrant { ... }
```

### Access Control

| Function | Access |
|----------|--------|
| Deposit | Public |
| Withdraw | Public |
| Claim | Public |
| Process Queues | Processor or Public |
| Set Parameters | Owner |
| Collect Fees | Owner |
| Upgrade | Owner |

## aHYPESeat Security Features

### Reentrancy Guard

All state-changing functions protected:

```solidity
modifier nonReentrant() {
    require(!_locked, "Reentrant");
    _locked = true;
    _;
    _locked = false;
}
```

### Checks-Effects-Interactions

All functions follow CEI pattern:

```solidity
function withdrawCollateral(uint256 amount) external nonReentrant {
    // Checks
    require(positions[msg.sender].hasSeat, "No seat");
    require(isHealthyAfterWithdrawal(amount), "Would become unhealthy");

    // Effects
    positions[msg.sender].collateral -= amount;

    // Interactions
    HYPE.transfer(msg.sender, amount);
}
```

### Health Invariant

Positions must remain healthy after any action:

```solidity
require(collateral >= debt, "Would become unhealthy");
```

Unhealthy positions can only be resolved by:
- Adding collateral
- Repaying fees
- Liquidation (`kick`)

### Enumerable Tracking

Seat holders tracked in array for iteration safety:

```solidity
address[] public seatHolders;
```

Removal swaps with last element to maintain O(1) operations:

```solidity
function _removeSeatHolder(address user) internal {
    // Find and swap with last
    seatHolders[index] = seatHolders[seatHolders.length - 1];
    seatHolders.pop();
}
```

### Parameter Validation

Admin parameter changes validated:

```solidity
require(_maxSeats >= occupiedSeats, "Cannot reduce below current");
require(_minFeePerSecond <= _maxFeePerSecond, "Invalid fee range");
require(_burnBps <= 10000, "Invalid burn rate");
require(_feeRecipient != address(0), "Invalid recipient");
```

## Trust Assumptions

### aHYPE

| Component | Trust Level | Notes |
|-----------|-------------|-------|
| Owner | High | Can upgrade contract, change parameters, collect fees |
| Processor | Medium | Can execute queue processing (timing control) |
| Validator | High | Delegated HYPE subject to validator behavior |
| HyperCore | High | Precompiles assumed to function correctly |

### aHYPESeat

| Component | Trust Level | Notes |
|-----------|-------------|-------|
| Owner | High | Can change fee parameters, max seats |
| aHYPE Token | High | Assumed standard ERC20 behavior |
| Liquidators | None | Anyone can liquidate unhealthy positions |

## Token Assumptions

aHYPESeat assumes the collateral token (aHYPE):

- Implements standard ERC20 interface
- No transfer fees or rebasing
- No blacklisting or pausing
- `transfer` and `transferFrom` return boolean

## Known Limitations

### aHYPE

1. **Unbonding Period**: Withdrawals may be delayed by staking unbonding period
2. **Queue Limits**: Maximum 100 pending operations per queue
3. **Block Processing**: Only one `processQueues()` call per block
4. **Validator Risk**: Delegated stake subject to slashing

### aHYPESeat

1. **Gas Costs**: `getHealthySeats()` may be expensive for large seat counts
2. **Front-Running**: Liquidations can be front-run by MEV bots
3. **Parameter Changes**: Fee changes affect all existing positions

## Audit Status

| Contract | Audit Status | Auditor |
|----------|--------------|---------|
| AlphaHYPEManager05 | TBD | - |
| SeatMarket01 | TBD | - |

## Bug Bounty

TBD - Contact information for security disclosures.

## Emergency Procedures

### aHYPE

1. **Pause Processing**: Set processor to non-operational address
2. **Prevent Deposits**: Set minDepositAmount to max uint256
3. **Allow Withdrawals**: Keep claim functionality operational

### aHYPESeat

1. **Prevent New Seats**: Set maxSeats to current occupiedSeats
2. **Maintain Liquidations**: Keep kick() operational for health
3. **Parameter Freeze**: Transfer ownership to timelock

## Recommendations for Integrators

1. **Monitor Health**: Regularly check position health for aHYPESeat
2. **Gas Reserves**: Maintain sufficient collateral buffer for fee accrual
3. **Event Indexing**: Index events for state reconstruction
4. **Price Oracle**: Use `getUnderlyingSupply()` / `getERC20Supply()` for exchange rate
5. **Rate Limits**: Respect queue caps when batching operations
