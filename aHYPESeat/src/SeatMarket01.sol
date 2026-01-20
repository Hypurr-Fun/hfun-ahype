// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
SeatMarket (utilization-based fees, absolute fee model)

Model:
- Each seat holder accrues fees at a rate between minFeePerSecond and maxFeePerSecond.
- Fee rate scales linearly with utilization = occupiedSeats / maxSeats.
- Users lock collateral in HYPE. They must keep collateral >= debt.
- If debt > collateral => position unhealthy; anyone can kick() to revoke the seat and seize collateral.

Fee calculation:
- Global `cumulativeFeePerSeat` grows by feePerSecond each second.
- Each user tracks their snapshot of this index when they join or settle.
- User debt = settledDebt + (cumulativeFeePerSeat - snapshot)

Notes:
- This is a fee/collateral escrow system (not a lender). Revenue flows to feeRecipient on repay/kick.
- Backend gating: require SeatMarket.isActive(user) == true.

Security:
- Uses checks-effects-interactions + reentrancy guard.
- Assumes HYPE is a standard ERC20 without transfer fees/rebasing.
*/

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function burn(uint256 amount) external;
}

abstract contract Ownable {
    address public owner;
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    constructor() { owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == owner, "NOT_OWNER"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "REENTRANT");
        _locked = 2;
        _;
        _locked = 1;
    }
}

contract SeatMarket is Ownable, ReentrancyGuard {
    // -------------------------
    // Constants / immutables
    // -------------------------
    uint256 public constant WAD = 1e18;

    IERC20 public immutable HYPE;

    // -------------------------
    // Seat + debt accounting
    // -------------------------
    uint256 public maxSeats;
    uint256 public occupiedSeats;

    // Cumulative fee per seat (additive, in HYPE with WAD precision)
    uint256 public cumulativeFeePerSeat;
    uint256 public lastAccrualTime;

    struct Position {
        bool hasSeat;
        uint256 collateral;        // HYPE locked
        uint256 settledDebt;       // crystallized debt from previous settlements
        uint256 feeIndexSnapshot;  // cumulativeFeePerSeat at join/settle time
    }

    mapping(address => Position) public positions;

    // Seat holder tracking (for enumeration)
    address[] public seatHolders;
    mapping(address => uint256) internal seatHolderIndex; // 1-indexed, 0 = not in array

    // -------------------------
    // Rate model parameters
    // -------------------------
    // feePerSecond = minFeePerSecond + (maxFeePerSecond - minFeePerSecond) * utilization
    // These are in HYPE per second per seat (WAD precision)
    // Example: 1e14 = 0.0001 HYPE/second ≈ 8.64 HYPE/day ≈ 3153 HYPE/year
    uint256 public minFeePerSecond;
    uint256 public maxFeePerSecond;

    address public feeRecipient;
    uint256 public burnBps; // basis points of fees to burn (10000 = 100%)

    // -------------------------
    // Events
    // -------------------------
    event Accrued(uint256 dt, uint256 feePerSecond, uint256 totalFeeAccrued, uint256 newCumulativeFee);
    event SeatPurchased(address indexed user, uint256 deposit);
    event CollateralAdded(address indexed user, uint256 amount);
    event FeesRepaid(address indexed user, uint256 amount);
    event FeeDistributed(uint256 toRecipient, uint256 burned);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event SeatKicked(address indexed user, address indexed kicker, uint256 collateralSeized, uint256 debtValue);
    event ParamsUpdated(uint256 maxSeats, uint256 minFeePerSecond, uint256 maxFeePerSecond, address feeRecipient, uint256 burnBps);

    // -------------------------
    // Constructor
    // -------------------------
    constructor(
        address hypeToken,
        uint256 _maxSeats,
        uint256 _minFeePerSecond,
        uint256 _maxFeePerSecond,
        address _feeRecipient,
        uint256 _burnBps
    ) {
        require(hypeToken != address(0), "HYPE_ZERO");
        require(_maxSeats > 0, "MAXSEATS_0");
        require(_feeRecipient != address(0), "FEE_RECIPIENT_0");
        require(_maxFeePerSecond >= _minFeePerSecond, "RATE_BOUNDS");
        require(_burnBps <= 10000, "BURN_BPS_TOO_HIGH");

        HYPE = IERC20(hypeToken);
        maxSeats = _maxSeats;
        minFeePerSecond = _minFeePerSecond;
        maxFeePerSecond = _maxFeePerSecond;
        feeRecipient = _feeRecipient;
        burnBps = _burnBps;
        lastAccrualTime = block.timestamp;

        emit ParamsUpdated(maxSeats, minFeePerSecond, maxFeePerSecond, feeRecipient, burnBps);
    }

    // -------------------------
    // Views
    // -------------------------
    function utilizationWad() public view returns (uint256) {
        if (maxSeats == 0) return 0;
        return (occupiedSeats * WAD) / maxSeats;
    }

    function feePerSecond() public view returns (uint256) {
        uint256 u = utilizationWad();
        if (maxFeePerSecond == minFeePerSecond) return minFeePerSecond;
        uint256 span = maxFeePerSecond - minFeePerSecond;
        return minFeePerSecond + (span * u) / WAD;
    }

    /// @notice Returns cumulativeFeePerSeat including pending accruals not yet applied
    function cumulativeFeePerSeatView() public view returns (uint256) {
        uint256 t = block.timestamp;
        uint256 last = lastAccrualTime;
        if (t <= last || occupiedSeats == 0) {
            return cumulativeFeePerSeat;
        }
        uint256 dt = t - last;
        uint256 rate = feePerSecond();
        return cumulativeFeePerSeat + (rate * dt);
    }

    function debtValueOf(address user) public view returns (uint256) {
        Position storage p = positions[user];
        if (!p.hasSeat) return 0;
        // debt = settledDebt + (cumulativeFeePerSeatView - snapshot)
        uint256 pendingFees = cumulativeFeePerSeatView() - p.feeIndexSnapshot;
        return p.settledDebt + pendingFees;
    }

    function isHealthy(address user) public view returns (bool) {
        Position storage p = positions[user];
        if (!p.hasSeat) return false;
        return p.collateral >= debtValueOf(user);
    }

    // -------------------------
    // Accrual
    // -------------------------
    function accrue() public {
        uint256 t = block.timestamp;
        uint256 last = lastAccrualTime;
        if (t <= last) return;

        uint256 dt = t - last;
        lastAccrualTime = t;

        // If no seats, no fees accrue
        if (occupiedSeats == 0) {
            emit Accrued(dt, 0, 0, cumulativeFeePerSeat);
            return;
        }

        uint256 rate = feePerSecond();
        uint256 feeAccrued = rate * dt;

        cumulativeFeePerSeat += feeAccrued;

        emit Accrued(dt, rate, feeAccrued, cumulativeFeePerSeat);
    }

    // -------------------------
    // Internal
    // -------------------------

    function _removeSeatHolder(address user) internal {
        uint256 idx = seatHolderIndex[user];
        if (idx == 0) return; // not in array

        uint256 lastIdx = seatHolders.length;
        if (idx != lastIdx) {
            // Swap with last element
            address lastUser = seatHolders[lastIdx - 1];
            seatHolders[idx - 1] = lastUser;
            seatHolderIndex[lastUser] = idx;
        }
        seatHolders.pop();
        seatHolderIndex[user] = 0;
    }

    /// @notice Distribute fees: split between feeRecipient and burning
    /// @dev Assumes tokens are already in this contract
    function _distributeFees(uint256 amount) internal {
        if (amount == 0) return;

        uint256 toBurn = (amount * burnBps) / 10000;
        uint256 toRecipient = amount - toBurn;

        if (toRecipient > 0) {
            require(HYPE.transfer(feeRecipient, toRecipient), "TRANSFER_FEE_FAIL");
        }
        if (toBurn > 0) {
            HYPE.burn(toBurn);
        }

        emit FeeDistributed(toRecipient, toBurn);
    }

    // -------------------------
    // Core actions
    // -------------------------

    /// @notice Occupy a seat by depositing collateral.
    /// @dev User starts with zero debt, fees begin accruing immediately.
    /// @dev Minimum deposit is one day of fees at the post-purchase utilization rate.
    function purchaseSeat(uint256 depositAmount) external nonReentrant {
        accrue();

        Position storage p = positions[msg.sender];
        require(!p.hasSeat, "ALREADY_HAS_SEAT");
        require(occupiedSeats < maxSeats, "NO_SEATS_AVAILABLE");
        require(depositAmount >= minDepositForSeat(), "DEPOSIT_BELOW_MIN");

        // Pull collateral
        require(HYPE.transferFrom(msg.sender, address(this), depositAmount), "TRANSFER_IN_FAIL");

        p.hasSeat = true;
        p.collateral = depositAmount;
        p.settledDebt = 0;
        p.feeIndexSnapshot = cumulativeFeePerSeat;

        // Track seat holder
        seatHolders.push(msg.sender);
        seatHolderIndex[msg.sender] = seatHolders.length; // 1-indexed

        occupiedSeats += 1;

        emit SeatPurchased(msg.sender, depositAmount);
    }

    function addCollateral(uint256 amount) external nonReentrant {
        require(amount > 0, "AMOUNT_0");
        Position storage p = positions[msg.sender];
        require(p.hasSeat, "NO_SEAT");

        require(HYPE.transferFrom(msg.sender, address(this), amount), "TRANSFER_IN_FAIL");
        p.collateral += amount;

        emit CollateralAdded(msg.sender, amount);
    }

    /// @notice Repay fees (reduce debt). Paid HYPE is split between feeRecipient and burning.
    function repayFees(uint256 amount) external nonReentrant {
        accrue();

        require(amount > 0, "AMOUNT_0");
        Position storage p = positions[msg.sender];
        require(p.hasSeat, "NO_SEAT");

        uint256 currentDebt = debtValueOf(msg.sender);
        require(currentDebt > 0, "NO_DEBT");

        // Cap repayment at current debt
        uint256 actualRepay = amount > currentDebt ? currentDebt : amount;

        // Pull tokens from user to this contract, then distribute
        require(HYPE.transferFrom(msg.sender, address(this), actualRepay), "TRANSFER_PAY_FAIL");
        _distributeFees(actualRepay);

        // Settle: new debt = currentDebt - actualRepay, reset snapshot
        p.settledDebt = currentDebt - actualRepay;
        p.feeIndexSnapshot = cumulativeFeePerSeat;

        emit FeesRepaid(msg.sender, actualRepay);
    }

    /// @notice Withdraw unlocked collateral as long as you remain healthy.
    function withdrawCollateral(uint256 amount) external nonReentrant {
        accrue();

        require(amount > 0, "AMOUNT_0");
        Position storage p = positions[msg.sender];
        require(p.hasSeat, "NO_SEAT");
        require(p.collateral >= amount, "INSUFFICIENT_COLLATERAL_BAL");

        // simulate withdrawal
        uint256 newColl = p.collateral - amount;
        uint256 debtVal = debtValueOf(msg.sender);
        require(newColl >= debtVal, "WOULD_BECOME_UNHEALTHY");

        p.collateral = newColl;
        require(HYPE.transfer(msg.sender, amount), "TRANSFER_OUT_FAIL");

        emit CollateralWithdrawn(msg.sender, amount);
    }

    /// @notice If user is unhealthy, anyone can kick them, revoking the seat and seizing collateral (split between feeRecipient and burning).
    function kick(address user) external nonReentrant {
        accrue();

        Position storage p = positions[user];
        require(p.hasSeat, "NO_SEAT");
        uint256 debtVal = debtValueOf(user);
        require(debtVal > p.collateral, "STILL_HEALTHY");

        uint256 seized = p.collateral;

        // Clear position
        _removeSeatHolder(user);
        occupiedSeats -= 1;
        p.hasSeat = false;
        p.collateral = 0;
        p.settledDebt = 0;
        p.feeIndexSnapshot = 0;

        // Distribute seized collateral (split between feeRecipient and burning)
        _distributeFees(seized);

        emit SeatKicked(user, msg.sender, seized, debtVal);
    }

    /// @notice Allow a seated user to exit voluntarily. Debt is settled from collateral, remainder returned.
    /// @dev If underwater, all collateral goes to fees (split between feeRecipient and burning) and user receives nothing.
    function exit() external nonReentrant {
        accrue();

        Position storage p = positions[msg.sender];
        require(p.hasSeat, "NO_SEAT");

        uint256 debtVal = debtValueOf(msg.sender);
        uint256 collateral = p.collateral;

        // If underwater, all collateral goes to fees, user gets nothing
        uint256 toFees = collateral < debtVal ? collateral : debtVal;
        uint256 refund = collateral - toFees;

        // Clear position
        _removeSeatHolder(msg.sender);
        occupiedSeats -= 1;
        p.hasSeat = false;
        p.collateral = 0;
        p.settledDebt = 0;
        p.feeIndexSnapshot = 0;

        // Distribute fees (split between feeRecipient and burning)
        _distributeFees(toFees);

        // Refund remaining collateral to user
        if (refund > 0) {
            require(HYPE.transfer(msg.sender, refund), "TRANSFER_OUT_FAIL");
        }

        emit FeesRepaid(msg.sender, toFees);
        emit CollateralWithdrawn(msg.sender, refund);
    }

    // -------------------------
    // Views
    // -------------------------

    /// @notice For API gating (backend checks this)
    function isActive(address user) external view returns (bool) {
        Position storage p = positions[user];
        if (!p.hasSeat) return false;
        return p.collateral >= debtValueOf(user);
    }

    /// @notice Returns all healthy seat holders (excludes unhealthy positions even if not yet kicked)
    function getHealthySeats() external view returns (address[] memory) {
        uint256 len = seatHolders.length;
        address[] memory temp = new address[](len);
        uint256 count = 0;

        for (uint256 i = 0; i < len; i++) {
            address user = seatHolders[i];
            if (isHealthy(user)) {
                temp[count] = user;
                count++;
            }
        }

        // Copy to correctly sized array
        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }
        return result;
    }

    // -------------------------
    // Admin
    // -------------------------
    function setParams(
        uint256 _maxSeats,
        uint256 _minFeePerSecond,
        uint256 _maxFeePerSecond,
        address _feeRecipient,
        uint256 _burnBps
    ) external onlyOwner {
        require(_maxSeats > 0, "MAXSEATS_0");
        require(_feeRecipient != address(0), "FEE_RECIPIENT_0");
        require(_maxFeePerSecond >= _minFeePerSecond, "RATE_BOUNDS");
        require(_maxSeats >= occupiedSeats, "MAX_LT_OCCUPIED");
        require(_burnBps <= 10000, "BURN_BPS_TOO_HIGH");

        accrue();

        maxSeats = _maxSeats;
        minFeePerSecond = _minFeePerSecond;
        maxFeePerSecond = _maxFeePerSecond;
        feeRecipient = _feeRecipient;
        burnBps = _burnBps;

        emit ParamsUpdated(maxSeats, minFeePerSecond, maxFeePerSecond, feeRecipient, burnBps);
    }

    // -------------------------
    // Convenience views
    // -------------------------

    /// @notice Returns fee per day per seat at current utilization (in HYPE, WAD precision)
    function feePerDay() external view returns (uint256) {
        return feePerSecond() * 1 days;
    }

    /// @notice Returns fee per year per seat at current utilization (in HYPE, WAD precision)
    function feePerYear() external view returns (uint256) {
        return feePerSecond() * 365 days;
    }

    /// @notice Returns minimum deposit required to purchase a seat (1 day of fees at post-purchase utilization)
    function minDepositForSeat() public view returns (uint256) {
        if (occupiedSeats >= maxSeats) return type(uint256).max; // no seats available
        uint256 newOccupied = occupiedSeats + 1;
        uint256 newUtilization = (newOccupied * WAD) / maxSeats;
        uint256 span = maxFeePerSecond - minFeePerSecond;
        uint256 newFeePerSecond = minFeePerSecond + (span * newUtilization) / WAD;
        return newFeePerSecond * 1 days;
    }
}
