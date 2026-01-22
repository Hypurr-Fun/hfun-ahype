# aHYPE - Alpha HYPE Liquid Staking Manager

AlphaHYPEManager is an upgradeable liquid staking vault for Hyperliquid's native HYPE token. It mints the wrapped Alpha HYPE token (`αHYPE`) and manages the full lifecycle of deposits, validator delegation, reward compounding, and redemptions through HyperCore precompiles.

## Key Features

- Queue-based deposits and withdrawals priced against real-time underlying HYPE backing
- Dual 0.1% protocol fee applied at mint and burn
- Eight-decimal ERC20 supply mirroring Hyperliquid accounting
- Automated bridging between EVM balance, Hyperliquid Spot, and staking delegations
- Pull-based withdrawals protecting against reentrancy and slashing events
- Role-gated processor for trusted queue execution

## Contract Addresses

| Contract          | Network | Address |
|-------------------|---------|---------|
| AlphaHYPEManager  | Hyperliquid EVM | 0xe44bd27c9f10fa2f89fdb3ab4b4f0e460da29ea8 |

## Token Model

| Property | Value |
|----------|-------|
| Name | Alpha HYPE |
| Symbol | αHYPE |
| Decimals | 8 |
| Standard | ERC20 (Upgradeable, Burnable) |

## Backing Composition

The underlying pool combines:
- Contract's EVM balance (scaled to 8 decimals)
- Hyperliquid spot holdings
- Delegated stake
- Undelegated stake
- Pending withdrawals (queried via `L1Read`)
