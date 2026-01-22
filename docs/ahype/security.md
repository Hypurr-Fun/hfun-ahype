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

## Trust Assumptions

| Component | Trust Level | Notes |
|-----------|-------------|-------|
| Owner | High | Can upgrade contract, change parameters, collect fees |
| Processor | Medium | Can execute queue processing (timing control) |
| Validator | High | Delegated HYPE subject to validator behavior |
| HyperCore | High | Precompiles assumed to function correctly |

## Known Limitations

1. **Unbonding Period**: Withdrawals may be delayed by staking unbonding period
2. **Queue Limits**: Maximum 100 pending operations per queue
3. **Block Processing**: Only one `processQueues()` call per block
4. **Validator Risk**: Delegated stake subject to slashing


## Audit Status

| Contract | Audit Status | Auditor |
|----------|--------------|---------|
| AlphaHYPEManager05 | TBD | - |

## Bug Bounty

TBD - Contact information for security disclosures.