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
- 
## Contract Addresses

| Contract          | Network | Address |
|-------------------|---------|---------|
| Sentry SeatMarket | Hyperliquid EVM | 0x6301983885567Ff45aa2A5E5E5456d23A76F7962 |

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
                │                             
                ▼                              
┌───────────────────────────┐   
│    HyperCore Precompiles  │ 
│                           │
│  - L1Read (state queries) │  
│  - L1Write (mutations)    │
│  - Validator delegation   │ 
│  - Spot balance mgmt      │
└───────────────────────────┘
```
