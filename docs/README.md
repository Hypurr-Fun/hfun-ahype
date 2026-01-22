# aHYPE Protocol

Technical documentation for the aHYPE liquid staking protocol and aHYPESeat market on Hyperliquid.

## Components

### aHYPE - Alpha HYPE Liquid Staking Manager

An upgradeable liquid staking vault for Hyperliquid's native HYPE token. Mints the wrapped Alpha HYPE token (`αHYPE`) and manages deposits, validator delegation, reward compounding, and redemptions through HyperCore precompiles.

**Key Features:**
- Queue-based deposits and withdrawals
- Real-time price against underlying HYPE backing
- 8-decimal ERC20 supply mirroring Hyperliquid accounting
- Automated bridging between EVM, Spot, and staking delegations

### aHYPESeat - Utilization-Based Seat Market

A fee/collateral escrow system providing gated access through limited "seats" using aHYPE token collateral.

**Key Features:**
- Fixed maximum seat capacity
- Utilization-based dynamic fee model
- Liquidation system for unhealthy positions
- Deflationary fee burn mechanism

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Interface                          │
└─────────────────────────────────────────────────────────────────┘
                                │
                ┌───────────────┴───────────────┐
                ▼                               ▼
┌───────────────────────────┐   ┌───────────────────────────────┐
│         aHYPE             │   │         aHYPESeat             │
│   AlphaHYPEManager05      │   │        SeatMarket01           │
│                           │   │                               │
│  - Deposit HYPE           │   │  - Purchase seat (αHYPE)      │
│  - Mint αHYPE             │   │  - Accrue utilization fees    │
│  - Withdraw αHYPE         │   │  - Liquidation system         │
│  - Claim HYPE             │   │  - Fee distribution + burn    │
└───────────────────────────┘   └───────────────────────────────┘
                │                               │
                ▼                               │
┌───────────────────────────┐                   │
│    HyperCore Precompiles  │                   │
│                           │                   │
│  - L1Read (state queries) │                   │
│  - L1Write (mutations)    │◄──────────────────┘
│  - Validator delegation   │      (uses αHYPE as collateral)
│  - Spot balance mgmt      │
└───────────────────────────┘
```

## Quick Links

| Resource | Description |
|----------|-------------|
| [aHYPE Interface](ahype/interface.md) | Full contract API reference |
| [aHYPESeat Interface](ahypeseat/interface.md) | Seat market API reference |
| [Deployment Guide](reference/deployment.md) | Deployment and upgrade instructions |
| [Security](reference/security.md) | Security model and considerations |

## Contract Addresses

| Contract          | Network | Address |
|-------------------|---------|---------|
| AlphaHYPEManager  | Hyperliquid EVM | 0xe44bd27c9f10fa2f89fdb3ab4b4f0e460da29ea8 |
| Sentry SeatMarket | Hyperliquid EVM | 0x6301983885567Ff45aa2A5E5E5456d23A76F7962 |

## Token Specifications

| Token | Symbol | Decimals | Type |
|-------|--------|----------|------|
| Alpha HYPE | αHYPE | 8 | ERC20 (Upgradeable) |
| HYPE | HYPE | 18 | Native |
