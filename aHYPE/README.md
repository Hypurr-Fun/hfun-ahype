# Alpha HYPE Liquid Staking Manager

AlphaHYPEManager03 is an upgradeable liquid staking vault for Hyperliquid's native HYPE token. It mints the wrapped Alpha HYPE token (rendered on-chain as `αHYPE`) and manages the full lifecycle of deposits, validator delegation, reward compounding, and redemptions through HyperCore precompiles.

## Key Features
- Queue-based deposits and withdrawals priced against the real-time underlying HYPE backing.
- Dual 0.1% protocol fee applied at mint and burn to fund the operator treasury.
- Eight-decimal ERC20 supply that mirrors Hyperliquid accounting while keeping exchange rates stable.
- Automated bridging between the EVM balance, Hyperliquid Spot, and staking delegations.
- Pull-based withdrawals that protect against reentrancy and slashing events.
- Role-gated processor that guarantees only a trusted agent executes queue processing.

## Token Model
- **Wrapped asset:** Alpha HYPE (`αHYPE`) extends `ERC20Upgradeable` with 8 decimals.
- **Backing:** The underlying pool combines the contract's EVM balance (scaled to 8 decimals), Hyperliquid spot holdings, delegated stake, undelegated stake, and pending withdrawals queried via `L1Read`.
- **Supply cap:** Optional `maxSupply` (uint64). A value of zero disables the cap.
- **Fees:** `FEE_BPS = 10` (0.1%) on both deposits and withdrawals. Fees accumulate on contract balance and can be harvested by the owner with `collectFees`.
- **Accounting helpers:**
  - `getERC20Supply()` = circulating `αHYPE` + queued withdrawal balance.
  - `getUnderlyingSupply()` = total HYPE backing less queued deposits, queued withdrawals, and accrued fees.

## Operational Flow

### Deposits
1. Users send HYPE to the contract (either native transfers or via `depositQueue` interaction).
2. Deposits are queued (`depositQueue`) after validation:
   - `msg.value` must meet `minDepositAmount`.
   - Amount must be a multiple of `10**10` wei to preserve 8-decimal arithmetic.
   - Queue length capped at 100 entries.
   - Optional `maxSupply` guard prevents over-minting.
3. `pendingDepositAmount` tracks unprocessed principal until `processQueues()` executes.

### Queue Processing
`processQueues()` can be called once per block by the designated `processor` (or anyone if unset). It:
- Revalidates solvency by comparing EVM holdings to owed withdrawals, pending deposits, and accrued fees.
- Reads HyperCore state via `L1Read.delegatorSummary` and `L1Read.spotBalance`.
- Prices deposits and withdrawals independently using `Math.mulDiv` for high-precision ratios.
- Executes `_processDeposits()` to mint `αHYPE` minus the mint fee.
- Executes `_processWithdrawals()` to settle requests when enough liquidity exists.
- Balances liquidity by:
  - Bridging HYPE from spot (`L1Write.spotSend`) if EVM liquidity is short.
  - Withdrawing or undelegating via `L1Write.stakingWithdraw` and `L1Write.tokenDelegate`.
  - Re-deploying idle HYPE to staking or spot when queues are clear, using the canonical `HYPE_SYSTEM_ADDRESS` (`0x2222...2222`).

### Withdrawals
1. Holders call `withdraw(amount)` which:
   - Requires enough `αHYPE` balance and a queue with <100 entries.
   - Locks an exchange rate snapshot (`pricePerTokenX18`) to shield users if slashing occurs before fulfillment.
   - Burns `αHYPE` immediately, increments `withdrawalAmount` and `virtualWithdrawalAmount`, and enqueues a `WithdrawalRequest`.
2. `_processWithdrawals()` settles requests when EVM liquidity permits:
   - Calculates the lesser of locked price and current spot price to apply slashing.
   - Applies the 0.1% burn fee, crediting users via `owedUnderlyingAmounts` and the protocol via `feeAmount`.
   - Removes fulfilled entries while preserving ordering.

### Claiming
Withdrawers call `claimWithdrawal()` after processing completes to pull their owed HYPE (scaled back to wei). The function zeroes state before transferring, guarding against reentrancy while emitting `WithdrawalClaimed`.

## Hyperliquid Integrations
- **Reads:** `L1Read.delegatorSummary` surfaces delegated, undelegated, and pending withdrawal balances; `L1Read.spotBalance` inspects spot holdings for the configured `hypeTokenIndex`.
- **Writes:** `L1Write.stakingDeposit`, `L1Write.stakingWithdraw`, `L1Write.tokenDelegate`, and `L1Write.spotSend` manage validator delegation and bridging.
- **System bridge:** Native transfers to `HYPE_SYSTEM_ADDRESS` move funds between Hyperliquid core and the EVM wrapper.

## Roles & Permissions
- **Owner (upgradeable):** Configures `maxSupply`, `minDepositAmount`, and `processor`, and harvests fees. Ownership is initialized to the deployer via `__Ownable_init`.
- **Processor:** Optional trusted executor allowed to run `processQueues()` once per block. If unset, any address may process.
- **Users:** Deposit by sending native HYPE, request withdrawals through `withdraw()`, and redeem with `claimWithdrawal()`.

## Events
- `DepositQueued`, `DepositProcessed` trace user inflows and minted supply.
- `WithdrawalQueued`, `WithdrawalProcessed`, `WithdrawalClaimed` document the redemption lifecycle.
- `EVMSend`, `SpotSend`, `StakingDeposit`, `StakingWithdraw`, `TokenDelegate` provide visibility into cross-domain liquidity management.
- `collectFees` does not emit a dedicated event; tracking relies on balance diffs.

## Safety Considerations
- Hard queue caps (100 entries) prevent unbounded loops.
- Pull-based withdrawals and `owedUnderlyingAmounts` mapping avoid reentrancy risks.
- One-process-per-block guard (`lastProcessedBlock`) blocks redundant processing.
- Precision scaling (`SCALE_18_TO_8`) and enforced multiples of `10**10` eliminate dust issues when converting between wei and 8-decimal accounting.
- Owner actions are limited to configuration and fee collection; core staking logic remains permissionless once deployed.

## Development
This repository uses Foundry for testing and scripting.

### Prerequisites
- Install [Foundry](https://book.getfoundry.sh/getting-started/installation) and run `foundryup`.

### Common Commands
```sh
forge build
forge test
forge fmt
forge snapshot
```

### Deployment Notes
- Update `validator` and `hypeTokenIndex` in deployment scripts before running any upgrade.
- Remember to initialize with `initialize(address validator, uint64 hypeTokenIndex)` immediately after deployment.
- Use `setProcessor`, `setMinDepositAmount`, and optional `setMaxSupply` to tune production parameters.

## Testing Guidance
- Unit tests should cover queue edge cases, fee accounting, and price boundary conditions.
- When integrating with Hyperliquid, mock `L1Read` and `L1Write` precompiles or fork the target network for end-to-end tests.

