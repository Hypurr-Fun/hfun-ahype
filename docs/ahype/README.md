# aHYPE - Alpha HYPE Liquid Staking Manager

AlphaHYPEManager is an upgradeable liquid staking vault for Hyperliquid's native HYPE token. It mints the wrapped Alpha HYPE token (`αHYPE`) and manages the full lifecycle of deposits, validator delegation, reward compounding, and redemptions through HyperCore precompiles.

## Key Features

- Queue-based deposits and withdrawals priced against real-time underlying HYPE backing
- Dual 0.1% protocol fee applied at mint and burn
- Eight-decimal ERC20 supply mirroring Hyperliquid accounting
- Automated bridging between EVM balance, Hyperliquid Spot, and staking delegations
- Pull-based withdrawals protecting against reentrancy and slashing events
- Role-gated processor for trusted queue execution

## Token Model

| Property | Value |
|----------|-------|
| Name | Alpha HYPE |
| Symbol | αHYPE |
| Decimals | 8 |
| Standard | ERC20 (Upgradeable, Burnable) |

### Backing Composition

The underlying pool combines:
- Contract's EVM balance (scaled to 8 decimals)
- Hyperliquid spot holdings
- Delegated stake
- Undelegated stake
- Pending withdrawals (queried via `L1Read`)

### Supply Accounting

```
getERC20Supply() = circulating αHYPE + queued withdrawal balance

getUnderlyingSupply() = total HYPE backing
                      - queued deposits
                      - queued withdrawals
                      - accrued fees
```

### Fee Structure

| Fee Type | Rate | Application |
|----------|------|-------------|
| Mint Fee | 0.1% (10 BPS) | Applied when minting αHYPE |
| Burn Fee | 0.1% (10 BPS) | Applied when burning αHYPE |

Fees accumulate on the contract and can be harvested by the owner via `collectFees()`.

## Operational Flow

### Deposit Flow

```
User sends HYPE ──► Deposit queued ──► processQueues() ──► αHYPE minted
                         │
                         ▼
                   Validation:
                   - msg.value >= minDepositAmount
                   - Amount is multiple of 10^10 wei
                   - Queue length < 100
                   - maxSupply not exceeded
```

### Withdrawal Flow

```
User calls withdraw(amount) ──► αHYPE burned ──► WithdrawalRequest queued
                                      │
                                      ▼
                               Price snapshot locked
                               (slashing protection)
                                      │
                                      ▼
                             processQueues() settles
                                      │
                                      ▼
                         User calls claimWithdrawal()
                                      │
                                      ▼
                              HYPE transferred
```

### Queue Processing

`processQueues()` executes once per block and:

1. Revalidates solvency by comparing EVM holdings to owed withdrawals
2. Reads HyperCore state via `L1Read.delegatorSummary` and `L1Read.spotBalance`
3. Prices deposits and withdrawals using high-precision ratios
4. Mints `αHYPE` minus mint fee for deposits
5. Settles withdrawal requests when liquidity exists
6. Balances liquidity by:
   - Bridging HYPE from spot if EVM liquidity is short
   - Withdrawing/undelegating from staking
   - Re-deploying idle HYPE to staking when queues are clear

## Roles & Permissions

| Role | Capabilities |
|------|--------------|
| **Owner** | Configure `maxSupply`, `minDepositAmount`, `processor`; harvest fees |
| **Processor** | Execute `processQueues()` once per block (if set) |
| **Users** | Deposit HYPE, request withdrawals, claim HYPE |

## Constants

```solidity
uint256 constant FEE_BPS = 10;                    // 0.1%
uint256 constant BPS_DENOMINATOR = 10_000;
uint256 constant SCALE_18_TO_8 = 1e10;
address constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;
```

## Storage Layout

### Structs

```solidity
struct DepositRequest {
    address depositor;
    uint256 amount;
}

struct WithdrawalRequest {
    address withdrawer;
    uint256 amount;
    uint256 pricePerTokenX18;  // Snapshot for slashing protection
}
```

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `validator` | `address` | Target validator for delegation |
| `hypeTokenIndex` | `uint64` | HYPE token index on Hyperliquid |
| `depositQueue` | `DepositRequest[]` | Pending deposits (max 100) |
| `pendingWithdrawalQueue` | `WithdrawalRequest[]` | Pending withdrawals |
| `pendingDepositAmount` | `uint256` | Total unprocessed deposit HYPE |
| `withdrawalAmount` | `uint256` | Total pending withdrawal αHYPE |
| `owedUnderlyingAmounts` | `mapping(address => uint256)` | HYPE owed per user |
| `feeAmount` | `uint256` | Accumulated protocol fees |
| `maxSupply` | `uint64` | Optional supply cap (0 = none) |
| `processor` | `address` | Designated processor (optional) |
| `minDepositAmount` | `uint256` | Minimum deposit threshold |
| `lastProcessedBlock` | `uint256` | One-per-block guard |
