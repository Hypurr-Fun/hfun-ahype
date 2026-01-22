# Security Model

Security considerations and safety features of the aHYPESeat protocol.

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

## Audit Status

| Contract | Audit Status | Auditor |
|----------|--------------|---------|
| SeatMarket01 | TBD | - |

## Bug Bounty

TBD - Contact information for security disclosures.

