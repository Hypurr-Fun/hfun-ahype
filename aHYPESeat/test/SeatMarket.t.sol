// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SeatMarket} from "../src/SeatMarket.sol";

contract MockHYPE {
    string public name = "HYPE";
    string public symbol = "HYPE";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 public totalBurned;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function burn(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        totalBurned += amount;
    }
}

contract SeatMarketTest is Test {
    SeatMarket public market;
    MockHYPE public hype;

    address public owner = address(this);
    address public feeRecipient = address(0xFEE);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xC4A);
    address public kicker = address(0xD1C8);

    uint256 constant WAD = 1e18;
    uint256 constant MAX_SEATS = 10;

    // Fee rates in HYPE per second (WAD precision)
    // MIN: 0.01 HYPE/day = 0.01e18 / 86400 ≈ 1.157e11 per second
    // MAX: 0.1 HYPE/day = 0.1e18 / 86400 ≈ 1.157e12 per second
    uint256 constant MIN_FEE_PER_SECOND = 1.157e11; // ~0.01 HYPE/day at 0% util
    uint256 constant MAX_FEE_PER_SECOND = 1.157e12; // ~0.1 HYPE/day at 100% util

    function setUp() public {
        hype = new MockHYPE();
        market = new SeatMarket(
            address(hype),
            MAX_SEATS,
            MIN_FEE_PER_SECOND,
            MAX_FEE_PER_SECOND,
            feeRecipient,
            0 // burnBps = 0 for existing tests
        );

        // Fund users
        hype.mint(alice, 1000 * WAD);
        hype.mint(bob, 1000 * WAD);
        hype.mint(charlie, 1000 * WAD);

        // Approve market
        vm.prank(alice);
        hype.approve(address(market), type(uint256).max);
        vm.prank(bob);
        hype.approve(address(market), type(uint256).max);
        vm.prank(charlie);
        hype.approve(address(market), type(uint256).max);
    }

    // ============================================
    // Basic Purchase Tests
    // ============================================

    function test_purchaseSeat_basic() public {
        vm.prank(alice);
        market.purchaseSeat(10 * WAD);

        (bool hasSeat, uint256 collateral, uint256 settledDebt, uint256 feeIndexSnapshot) = market.positions(alice);
        assertTrue(hasSeat);
        assertEq(collateral, 10 * WAD);
        assertEq(settledDebt, 0); // Starts with zero debt
        assertEq(feeIndexSnapshot, 0); // cumulativeFeePerSeat is 0 at start
        assertEq(market.occupiedSeats(), 1);
    }

    function test_purchaseSeat_startsWithZeroDebt() public {
        vm.prank(alice);
        market.purchaseSeat(10 * WAD);

        uint256 debt = market.debtValueOf(alice);
        assertEq(debt, 0); // No debt initially
    }

    function test_purchaseSeat_revertOnDuplicate() public {
        vm.prank(alice);
        market.purchaseSeat(10 * WAD);

        vm.prank(alice);
        vm.expectRevert("ALREADY_HAS_SEAT");
        market.purchaseSeat(10 * WAD);
    }

    function test_purchaseSeat_revertWhenNoSeatsAvailable() public {
        // Fill all seats
        for (uint256 i = 0; i < MAX_SEATS; i++) {
            address user = address(uint160(0x1000 + i));
            hype.mint(user, 100 * WAD);
            vm.startPrank(user);
            hype.approve(address(market), type(uint256).max);
            market.purchaseSeat(10 * WAD);
            vm.stopPrank();
        }

        assertEq(market.occupiedSeats(), MAX_SEATS);

        vm.prank(alice);
        vm.expectRevert("NO_SEATS_AVAILABLE");
        market.purchaseSeat(10 * WAD);
    }

    // ============================================
    // Debt Accrual Tests
    // ============================================

    function test_debtAccrues_overTime() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        uint256 initialDebt = market.debtValueOf(alice);
        assertEq(initialDebt, 0); // Starts at zero

        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days);
        market.accrue();

        uint256 newDebt = market.debtValueOf(alice);
        assertGt(newDebt, 0);

        // At 10% utilization, fee should be ~0.019 HYPE/day
        // (minFee + 10% of spread)
        console.log("Debt after 1 day:", newDebt);
        console.log("Expected ~0.019 HYPE: 19000000000000000");
    }

    function test_debtAccrual_linearOverTime() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        vm.warp(block.timestamp + 1 days);
        market.accrue();
        uint256 debt1Day = market.debtValueOf(alice);

        vm.warp(block.timestamp + 1 days);
        market.accrue();
        uint256 debt2Days = market.debtValueOf(alice);

        // Debt should double (linear accrual)
        assertApproxEqRel(debt2Days, debt1Day * 2, 0.01e18); // 1% tolerance

        console.log("Debt after 1 day:", debt1Day);
        console.log("Debt after 2 days:", debt2Days);
    }

    function test_debtAccrual_allUsersAccrueSameRate() public {
        // Alice and Bob both get seats at the same time
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        vm.prank(bob);
        market.purchaseSeat(100 * WAD);

        vm.warp(block.timestamp + 30 days);
        market.accrue();

        uint256 aliceDebt = market.debtValueOf(alice);
        uint256 bobDebt = market.debtValueOf(bob);

        // Both should have same debt (joined at same time, same fee rate)
        assertEq(aliceDebt, bobDebt);
        console.log("Both users debt after 30 days:", aliceDebt);
    }

    function test_debtAccrual_lateJoinerPaysLess() public {
        // Alice joins first
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        vm.warp(block.timestamp + 15 days);

        // Bob joins 15 days later
        vm.prank(bob);
        market.purchaseSeat(100 * WAD);

        vm.warp(block.timestamp + 15 days);
        market.accrue();

        uint256 aliceDebt = market.debtValueOf(alice);
        uint256 bobDebt = market.debtValueOf(bob);

        // Alice has been in for 30 days, Bob for 15 days
        assertGt(aliceDebt, bobDebt);
        console.log("Alice debt (30 days):", aliceDebt);
        console.log("Bob debt (15 days):", bobDebt);
    }

    function test_debtAccrual_higherWithMoreUtilization() public {
        // Test at low utilization (1 seat = 10%)
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        uint256 feeRateLow = market.feePerSecond();

        // Fill more seats to increase utilization
        for (uint256 i = 0; i < 8; i++) {
            address user = address(uint160(0x1000 + i));
            hype.mint(user, 100 * WAD);
            vm.startPrank(user);
            hype.approve(address(market), type(uint256).max);
            market.purchaseSeat(10 * WAD);
            vm.stopPrank();
        }

        // Now at 90% utilization
        uint256 feeRateHigh = market.feePerSecond();

        assertGt(feeRateHigh, feeRateLow);
        console.log("Fee rate at 10% utilization:", feeRateLow);
        console.log("Fee rate at 90% utilization:", feeRateHigh);
    }

    function test_feePerDay_convenience() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        uint256 feePerDay = market.feePerDay();
        uint256 feePerYear = market.feePerYear();

        console.log("Fee per day at 10% util:", feePerDay);
        console.log("Fee per year at 10% util:", feePerYear);

        // Should be consistent
        assertApproxEqRel(feePerYear, feePerDay * 365, 0.01e18);
    }

    // ============================================
    // Kick (Liquidation) Tests
    // ============================================

    function test_kick_undercollateralizedUser() public {
        // Alice gets a seat with minimal collateral
        vm.prank(alice);
        market.purchaseSeat(1 * WAD);

        assertTrue(market.isHealthy(alice));
        assertEq(market.debtValueOf(alice), 0);

        // Advance time until debt exceeds collateral
        // At ~0.019 HYPE/day, 1 HYPE collateral lasts ~52 days
        vm.warp(block.timestamp + 60 days);
        market.accrue();

        uint256 aliceDebt = market.debtValueOf(alice);
        (,uint256 aliceCollateral,,) = market.positions(alice);

        console.log("Alice debt after 60 days:", aliceDebt);
        console.log("Alice collateral:", aliceCollateral);

        if (aliceDebt > aliceCollateral) {
            assertFalse(market.isHealthy(alice));

            uint256 feeRecipientBalBefore = hype.balanceOf(feeRecipient);

            vm.prank(kicker);
            market.kick(alice);

            // Alice should no longer have a seat
            (bool hasSeat,,,) = market.positions(alice);
            assertFalse(hasSeat);

            // Collateral should go to feeRecipient
            uint256 feeRecipientBalAfter = hype.balanceOf(feeRecipient);
            assertEq(feeRecipientBalAfter - feeRecipientBalBefore, aliceCollateral);

            assertEq(market.occupiedSeats(), 0);
        }
    }

    function test_kick_revertsIfHealthy() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        assertTrue(market.isHealthy(alice));

        vm.prank(kicker);
        vm.expectRevert("STILL_HEALTHY");
        market.kick(alice);
    }

    function test_kick_anyoneCanKick() public {
        vm.prank(alice);
        market.purchaseSeat(1 * WAD);

        vm.warp(block.timestamp + 100 days);
        market.accrue();

        uint256 aliceDebt = market.debtValueOf(alice);
        (,uint256 aliceCollateral,,) = market.positions(alice);

        if (aliceDebt > aliceCollateral) {
            address randomKicker = address(0x999);
            vm.prank(randomKicker);
            market.kick(alice);

            (bool hasSeat,,,) = market.positions(alice);
            assertFalse(hasSeat);
        }
    }

    // ============================================
    // Health Check Tests
    // ============================================

    function test_isHealthy_trueInitially() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        assertTrue(market.isHealthy(alice));
        assertTrue(market.isActive(alice));
    }

    function test_isHealthy_falseWithoutSeat() public {
        assertFalse(market.isHealthy(alice));
        assertFalse(market.isActive(alice));
    }

    function test_isHealthy_degradesOverTime() public {
        vm.prank(alice);
        market.purchaseSeat(1 * WAD);

        assertTrue(market.isHealthy(alice));

        // Check when it becomes unhealthy
        for (uint256 day = 10; day <= 100; day += 10) {
            vm.warp(block.timestamp + 10 days);
            market.accrue();

            bool healthy = market.isHealthy(alice);
            uint256 debt = market.debtValueOf(alice);
            (,uint256 coll,,) = market.positions(alice);

            console.log("Day %d - Debt: %d, Collateral: %d", day, debt, coll);

            if (!healthy) {
                console.log("Became unhealthy around day", day);
                break;
            }
        }
    }

    // ============================================
    // Collateral Management Tests
    // ============================================

    function test_addCollateral_increasesHealth() public {
        vm.prank(alice);
        market.purchaseSeat(2 * WAD);

        uint256 initialColl;
        (,initialColl,,) = market.positions(alice);

        vm.prank(alice);
        market.addCollateral(10 * WAD);

        uint256 newColl;
        (,newColl,,) = market.positions(alice);

        assertEq(newColl, initialColl + 10 * WAD);
        assertTrue(market.isHealthy(alice));
    }

    function test_withdrawCollateral_whenNoDebt() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        // Immediately withdraw most (no debt yet)
        vm.prank(alice);
        market.withdrawCollateral(99 * WAD);

        (,uint256 coll,,) = market.positions(alice);
        assertEq(coll, 1 * WAD);
        assertTrue(market.isHealthy(alice));
    }

    function test_withdrawCollateral_maintainsHealth() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        // Accrue some debt
        vm.warp(block.timestamp + 30 days);
        market.accrue();

        uint256 debt = market.debtValueOf(alice);

        // Try to withdraw, leaving enough for debt
        uint256 withdrawable = 100 * WAD - debt - 1; // leave 1 wei buffer

        vm.prank(alice);
        market.withdrawCollateral(withdrawable);

        assertTrue(market.isHealthy(alice));
    }

    function test_withdrawCollateral_revertsIfWouldBecomeUnhealthy() public {
        vm.prank(alice);
        market.purchaseSeat(10 * WAD);

        // Accrue significant debt
        vm.warp(block.timestamp + 100 days);
        market.accrue();

        uint256 debt = market.debtValueOf(alice);
        (,uint256 coll,,) = market.positions(alice);

        // Try to withdraw more than allowed
        if (coll > debt) {
            uint256 excess = coll - debt;
            vm.prank(alice);
            vm.expectRevert("WOULD_BECOME_UNHEALTHY");
            market.withdrawCollateral(excess + 1);
        }
    }

    // ============================================
    // Fee Repayment Tests
    // ============================================

    function test_repayFees_reducesDebt() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        vm.warp(block.timestamp + 30 days);
        market.accrue();

        uint256 debtBefore = market.debtValueOf(alice);
        assertGt(debtBefore, 0);

        // Repay half
        vm.prank(alice);
        market.repayFees(debtBefore / 2);

        uint256 debtAfter = market.debtValueOf(alice);
        assertApproxEqRel(debtAfter, debtBefore / 2, 0.01e18);

        console.log("Debt before:", debtBefore);
        console.log("Debt after:", debtAfter);
    }

    function test_repayFees_canRepayAll() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        vm.warp(block.timestamp + 30 days);
        market.accrue();

        uint256 debtBefore = market.debtValueOf(alice);

        // Repay all + extra (should cap at actual debt)
        vm.prank(alice);
        market.repayFees(debtBefore + 10 * WAD);

        uint256 debtAfter = market.debtValueOf(alice);
        assertEq(debtAfter, 0);
    }

    function test_repayFees_goesToFeeRecipient() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        vm.warp(block.timestamp + 30 days);
        market.accrue();

        uint256 debt = market.debtValueOf(alice);
        uint256 feeRecipientBalBefore = hype.balanceOf(feeRecipient);

        vm.prank(alice);
        market.repayFees(debt);

        uint256 feeRecipientBalAfter = hype.balanceOf(feeRecipient);
        assertEq(feeRecipientBalAfter - feeRecipientBalBefore, debt);
    }

    function test_repayFees_revertsWithNoDebt() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        // No time passed, no debt
        vm.prank(alice);
        vm.expectRevert("NO_DEBT");
        market.repayFees(1 * WAD);
    }

    function test_repayFees_partialThenContinue() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        vm.warp(block.timestamp + 30 days);
        market.accrue();

        uint256 debt1 = market.debtValueOf(alice);

        // Repay half
        vm.prank(alice);
        market.repayFees(debt1 / 2);

        // Continue accruing
        vm.warp(block.timestamp + 30 days);
        market.accrue();

        uint256 debt2 = market.debtValueOf(alice);

        // Should have ~half original + 30 more days
        console.log("Debt after 30 days:", debt1);
        console.log("Debt after repay + 30 more days:", debt2);

        assertGt(debt2, debt1 / 2);
    }

    // ============================================
    // Exit Tests
    // ============================================

    function test_exit_immediately() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        // Exit immediately (no debt accrued)
        uint256 balBefore = hype.balanceOf(alice);

        vm.prank(alice);
        market.exit();

        uint256 balAfter = hype.balanceOf(alice);
        assertEq(balAfter - balBefore, 100 * WAD);

        (bool hasSeat,,,) = market.positions(alice);
        assertFalse(hasSeat);
        assertEq(market.occupiedSeats(), 0);
    }

    function test_exit_afterRepayingDebt() public {
        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        vm.warp(block.timestamp + 30 days);
        market.accrue();

        // Repay all debt first
        uint256 debt = market.debtValueOf(alice);
        vm.prank(alice);
        market.repayFees(debt);

        // Now exit
        uint256 balBefore = hype.balanceOf(alice);
        (,uint256 coll,,) = market.positions(alice);

        vm.prank(alice);
        market.exit();

        uint256 balAfter = hype.balanceOf(alice);
        assertEq(balAfter - balBefore, coll);
    }

    function test_exit_whenUnderwater() public {
        vm.prank(alice);
        market.purchaseSeat(1 * WAD);

        // Warp until debt exceeds collateral
        vm.warp(block.timestamp + 60 days);
        market.accrue();

        // Should be underwater now
        uint256 debt = market.debtValueOf(alice);
        assertGt(debt, 1 * WAD);

        uint256 aliceBalBefore = hype.balanceOf(alice);
        uint256 feeRecipientBalBefore = hype.balanceOf(feeRecipient);

        // User can still exit when underwater
        vm.prank(alice);
        market.exit();

        // Position is cleared
        (bool hasSeat, uint256 coll,,) = market.positions(alice);
        assertFalse(hasSeat);
        assertEq(coll, 0);

        // User receives nothing (balance unchanged)
        assertEq(hype.balanceOf(alice), aliceBalBefore);

        // All collateral (1 WAD) goes to feeRecipient
        assertEq(hype.balanceOf(feeRecipient), feeRecipientBalBefore + 1 * WAD);

        // Seat count decremented
        assertEq(market.occupiedSeats(), 0);
    }

    // ============================================
    // Edge Cases
    // ============================================

    function test_noAccrual_whenNoSeats() public {
        uint256 initialCumFee = market.cumulativeFeePerSeat();

        vm.warp(block.timestamp + 365 days);
        market.accrue();

        assertEq(market.cumulativeFeePerSeat(), initialCumFee);
    }

    function test_utilization_affectsRate() public {
        assertEq(market.utilizationWad(), 0);
        assertEq(market.feePerSecond(), MIN_FEE_PER_SECOND);

        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        // 1/10 = 10%
        assertEq(market.utilizationWad(), WAD / 10);

        vm.prank(bob);
        market.purchaseSeat(100 * WAD);

        // 2/10 = 20%
        assertEq(market.utilizationWad(), 2 * WAD / 10);
    }

    function test_feePerSecond_scales() public {
        uint256 rateAt0 = market.feePerSecond();
        assertEq(rateAt0, MIN_FEE_PER_SECOND);

        // Fill half the seats
        for (uint256 i = 0; i < 5; i++) {
            address user = address(uint160(0x1000 + i));
            hype.mint(user, 100 * WAD);
            vm.startPrank(user);
            hype.approve(address(market), type(uint256).max);
            market.purchaseSeat(10 * WAD);
            vm.stopPrank();
        }

        uint256 rateAt50 = market.feePerSecond();
        uint256 expectedAt50 = MIN_FEE_PER_SECOND + (MAX_FEE_PER_SECOND - MIN_FEE_PER_SECOND) / 2;
        assertEq(rateAt50, expectedAt50);

        // Fill all seats
        for (uint256 i = 5; i < 10; i++) {
            address user = address(uint160(0x1000 + i));
            hype.mint(user, 100 * WAD);
            vm.startPrank(user);
            hype.approve(address(market), type(uint256).max);
            market.purchaseSeat(10 * WAD);
            vm.stopPrank();
        }

        uint256 rateAt100 = market.feePerSecond();
        assertEq(rateAt100, MAX_FEE_PER_SECOND);

        console.log("Rate at 0%:", rateAt0);
        console.log("Rate at 50%:", rateAt50);
        console.log("Rate at 100%:", rateAt100);
    }

    // ============================================
    // Fuzz Tests
    // ============================================

    function testFuzz_purchaseSeat_anyDeposit(uint256 deposit) public {
        uint256 minDeposit = market.minDepositForSeat();
        deposit = bound(deposit, minDeposit, 1000 * WAD);

        hype.mint(alice, deposit);
        vm.startPrank(alice);
        hype.approve(address(market), deposit);
        market.purchaseSeat(deposit);
        vm.stopPrank();

        assertTrue(market.isHealthy(alice));
        assertEq(market.debtValueOf(alice), 0); // No initial debt
    }

    function testFuzz_kickThreshold(uint256 collateral, uint256 daysElapsed) public {
        collateral = bound(collateral, 0.1e18, 10 * WAD);
        daysElapsed = bound(daysElapsed, 1, 365 * 5);

        hype.mint(alice, collateral);
        vm.startPrank(alice);
        hype.approve(address(market), collateral);
        market.purchaseSeat(collateral);
        vm.stopPrank();

        vm.warp(block.timestamp + daysElapsed * 1 days);
        market.accrue();

        uint256 debt = market.debtValueOf(alice);
        (,uint256 coll,,) = market.positions(alice);

        bool healthy = market.isHealthy(alice);

        if (debt > coll) {
            assertFalse(healthy);
            vm.prank(kicker);
            market.kick(alice);
            (bool hasSeat,,,) = market.positions(alice);
            assertFalse(hasSeat);
        } else {
            assertTrue(healthy);
            vm.prank(kicker);
            vm.expectRevert("STILL_HEALTHY");
            market.kick(alice);
        }
    }

    function testFuzz_repayAndContinue(uint256 repayFraction) public {
        repayFraction = bound(repayFraction, 1, 100);

        vm.prank(alice);
        market.purchaseSeat(100 * WAD);

        vm.warp(block.timestamp + 30 days);
        market.accrue();

        uint256 debt = market.debtValueOf(alice);
        uint256 repayAmount = (debt * repayFraction) / 100;

        if (repayAmount > 0) {
            vm.prank(alice);
            market.repayFees(repayAmount);

            uint256 remaining = market.debtValueOf(alice);
            assertApproxEqAbs(remaining, debt - repayAmount, 1); // Allow 1 wei rounding
        }
    }

    // ============================================
    // Seat Holder Tracking & getHealthySeats
    // ============================================

    function test_seatHolders_addedOnPurchase() public {
        // Initially empty
        address[] memory seats = market.getHealthySeats();
        assertEq(seats.length, 0);

        vm.prank(alice);
        market.purchaseSeat(10 * WAD);

        seats = market.getHealthySeats();
        assertEq(seats.length, 1);
        assertEq(seats[0], alice);
        assertEq(market.seatHolders(0), alice);

        vm.prank(bob);
        market.purchaseSeat(10 * WAD);

        seats = market.getHealthySeats();
        assertEq(seats.length, 2);
        assertEq(market.seatHolders(1), bob);
    }

    function test_seatHolders_removedOnExit() public {
        vm.prank(alice);
        market.purchaseSeat(10 * WAD);
        vm.prank(bob);
        market.purchaseSeat(10 * WAD);

        address[] memory seats = market.getHealthySeats();
        assertEq(seats.length, 2);

        vm.prank(alice);
        market.exit();

        seats = market.getHealthySeats();
        assertEq(seats.length, 1);
        assertEq(seats[0], bob);
    }

    function test_seatHolders_removedOnKick() public {
        vm.prank(alice);
        market.purchaseSeat(1 * WAD);
        vm.prank(bob);
        market.purchaseSeat(10 * WAD);

        // Warp until alice is underwater
        vm.warp(block.timestamp + 60 days);
        market.accrue();

        assertFalse(market.isHealthy(alice));
        assertTrue(market.isHealthy(bob));

        vm.prank(kicker);
        market.kick(alice);

        address[] memory seats = market.getHealthySeats();
        assertEq(seats.length, 1);
        assertEq(seats[0], bob);
    }

    function test_getHealthySeats_excludesUnhealthy() public {
        vm.prank(alice);
        market.purchaseSeat(1 * WAD);
        vm.prank(bob);
        market.purchaseSeat(100 * WAD);
        vm.prank(charlie);
        market.purchaseSeat(1 * WAD);

        address[] memory seats = market.getHealthySeats();
        assertEq(seats.length, 3);

        // Warp until alice and charlie are underwater (small collateral)
        vm.warp(block.timestamp + 60 days);
        market.accrue();

        assertFalse(market.isHealthy(alice));
        assertTrue(market.isHealthy(bob));
        assertFalse(market.isHealthy(charlie));

        // getHealthySeats should only return bob
        seats = market.getHealthySeats();
        assertEq(seats.length, 1);
        assertEq(seats[0], bob);
    }

    function test_getHealthySeats_emptyWhenNoSeats() public {
        address[] memory seats = market.getHealthySeats();
        assertEq(seats.length, 0);
    }

    function test_seatHolders_swapAndPopWorksCorrectly() public {
        // Add 3 users
        vm.prank(alice);
        market.purchaseSeat(10 * WAD);
        vm.prank(bob);
        market.purchaseSeat(10 * WAD);
        vm.prank(charlie);
        market.purchaseSeat(10 * WAD);

        // Array should be [alice, bob, charlie]
        assertEq(market.seatHolders(0), alice);
        assertEq(market.seatHolders(1), bob);
        assertEq(market.seatHolders(2), charlie);

        // Remove alice (first element) - should swap with charlie
        vm.prank(alice);
        market.exit();

        // Array should now be [charlie, bob]
        assertEq(market.seatHolders(0), charlie);
        assertEq(market.seatHolders(1), bob);

        address[] memory seats = market.getHealthySeats();
        assertEq(seats.length, 2);
    }

    function test_seatHolders_removeMiddleElement() public {
        vm.prank(alice);
        market.purchaseSeat(10 * WAD);
        vm.prank(bob);
        market.purchaseSeat(10 * WAD);
        vm.prank(charlie);
        market.purchaseSeat(10 * WAD);

        // Remove bob (middle element)
        vm.prank(bob);
        market.exit();

        // Array should be [alice, charlie]
        assertEq(market.seatHolders(0), alice);
        assertEq(market.seatHolders(1), charlie);

        address[] memory seats = market.getHealthySeats();
        assertEq(seats.length, 2);
    }

    function test_seatHolders_removeLastElement() public {
        vm.prank(alice);
        market.purchaseSeat(10 * WAD);
        vm.prank(bob);
        market.purchaseSeat(10 * WAD);

        // Remove bob (last element)
        vm.prank(bob);
        market.exit();

        // Array should be [alice]
        assertEq(market.seatHolders(0), alice);

        address[] memory seats = market.getHealthySeats();
        assertEq(seats.length, 1);
        assertEq(seats[0], alice);
    }

    // ============================================
    // Fee Burn Split Tests
    // ============================================

    function test_burnBps_splitsFees() public {
        // Create a new market with 50% burn rate
        SeatMarket marketWithBurn = new SeatMarket(
            address(hype),
            MAX_SEATS,
            MIN_FEE_PER_SECOND,
            MAX_FEE_PER_SECOND,
            feeRecipient,
            5000 // 50% burn
        );

        hype.mint(alice, 100 * WAD);
        vm.startPrank(alice);
        hype.approve(address(marketWithBurn), type(uint256).max);
        marketWithBurn.purchaseSeat(100 * WAD);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);
        marketWithBurn.accrue();

        uint256 debt = marketWithBurn.debtValueOf(alice);
        uint256 feeRecipientBalBefore = hype.balanceOf(feeRecipient);
        uint256 burnedBefore = hype.totalBurned();

        vm.prank(alice);
        marketWithBurn.repayFees(debt);

        uint256 feeRecipientBalAfter = hype.balanceOf(feeRecipient);
        uint256 burnedAfter = hype.totalBurned();

        uint256 toRecipient = feeRecipientBalAfter - feeRecipientBalBefore;
        uint256 burned = burnedAfter - burnedBefore;

        // Should be approximately 50/50 split
        assertApproxEqRel(toRecipient, debt / 2, 0.01e18);
        assertApproxEqRel(burned, debt / 2, 0.01e18);
        assertEq(toRecipient + burned, debt);

        console.log("Total debt:", debt);
        console.log("To feeRecipient:", toRecipient);
        console.log("Burned:", burned);
    }

    function test_burnBps_100PercentBurn() public {
        // Create a new market with 100% burn rate
        SeatMarket marketWithBurn = new SeatMarket(
            address(hype),
            MAX_SEATS,
            MIN_FEE_PER_SECOND,
            MAX_FEE_PER_SECOND,
            feeRecipient,
            10000 // 100% burn
        );

        hype.mint(alice, 100 * WAD);
        vm.startPrank(alice);
        hype.approve(address(marketWithBurn), type(uint256).max);
        marketWithBurn.purchaseSeat(100 * WAD);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);
        marketWithBurn.accrue();

        uint256 debt = marketWithBurn.debtValueOf(alice);
        uint256 feeRecipientBalBefore = hype.balanceOf(feeRecipient);
        uint256 burnedBefore = hype.totalBurned();

        vm.prank(alice);
        marketWithBurn.repayFees(debt);

        uint256 feeRecipientBalAfter = hype.balanceOf(feeRecipient);
        uint256 burnedAfter = hype.totalBurned();

        // All should be burned, nothing to feeRecipient
        assertEq(feeRecipientBalAfter - feeRecipientBalBefore, 0);
        assertEq(burnedAfter - burnedBefore, debt);
    }

    function test_burnBps_exitSplitsFees() public {
        // Create a new market with 30% burn rate
        SeatMarket marketWithBurn = new SeatMarket(
            address(hype),
            MAX_SEATS,
            MIN_FEE_PER_SECOND,
            MAX_FEE_PER_SECOND,
            feeRecipient,
            3000 // 30% burn
        );

        hype.mint(alice, 100 * WAD);
        vm.startPrank(alice);
        hype.approve(address(marketWithBurn), type(uint256).max);
        marketWithBurn.purchaseSeat(100 * WAD);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);
        marketWithBurn.accrue();

        uint256 debt = marketWithBurn.debtValueOf(alice);
        uint256 feeRecipientBalBefore = hype.balanceOf(feeRecipient);
        uint256 burnedBefore = hype.totalBurned();

        vm.prank(alice);
        marketWithBurn.exit();

        uint256 feeRecipientBalAfter = hype.balanceOf(feeRecipient);
        uint256 burnedAfter = hype.totalBurned();

        uint256 toRecipient = feeRecipientBalAfter - feeRecipientBalBefore;
        uint256 burned = burnedAfter - burnedBefore;

        // Should be 70/30 split (70% to recipient, 30% burned)
        assertApproxEqRel(toRecipient, (debt * 7000) / 10000, 0.01e18);
        assertApproxEqRel(burned, (debt * 3000) / 10000, 0.01e18);
        assertEq(toRecipient + burned, debt);
    }

    function test_burnBps_kickSplitsFees() public {
        // Create a new market with 25% burn rate
        SeatMarket marketWithBurn = new SeatMarket(
            address(hype),
            MAX_SEATS,
            MIN_FEE_PER_SECOND,
            MAX_FEE_PER_SECOND,
            feeRecipient,
            2500 // 25% burn
        );

        hype.mint(alice, 1 * WAD);
        vm.startPrank(alice);
        hype.approve(address(marketWithBurn), type(uint256).max);
        marketWithBurn.purchaseSeat(1 * WAD);
        vm.stopPrank();

        // Warp until underwater
        vm.warp(block.timestamp + 60 days);
        marketWithBurn.accrue();

        uint256 collateral = 1 * WAD;
        uint256 feeRecipientBalBefore = hype.balanceOf(feeRecipient);
        uint256 burnedBefore = hype.totalBurned();

        vm.prank(kicker);
        marketWithBurn.kick(alice);

        uint256 feeRecipientBalAfter = hype.balanceOf(feeRecipient);
        uint256 burnedAfter = hype.totalBurned();

        uint256 toRecipient = feeRecipientBalAfter - feeRecipientBalBefore;
        uint256 burned = burnedAfter - burnedBefore;

        // Collateral (1 WAD) should be split 75/25
        assertEq(toRecipient, (collateral * 7500) / 10000);
        assertEq(burned, (collateral * 2500) / 10000);
        assertEq(toRecipient + burned, collateral);
    }

    function test_burnBps_setParams() public {
        assertEq(market.burnBps(), 0);

        market.setParams(MAX_SEATS, MIN_FEE_PER_SECOND, MAX_FEE_PER_SECOND, feeRecipient, 5000);
        assertEq(market.burnBps(), 5000);
    }

    function test_burnBps_revertIfTooHigh() public {
        vm.expectRevert("BURN_BPS_TOO_HIGH");
        new SeatMarket(
            address(hype),
            MAX_SEATS,
            MIN_FEE_PER_SECOND,
            MAX_FEE_PER_SECOND,
            feeRecipient,
            10001 // > 100%
        );
    }

    function test_burnBps_setParams_revertIfTooHigh() public {
        vm.expectRevert("BURN_BPS_TOO_HIGH");
        market.setParams(MAX_SEATS, MIN_FEE_PER_SECOND, MAX_FEE_PER_SECOND, feeRecipient, 10001);
    }
}
