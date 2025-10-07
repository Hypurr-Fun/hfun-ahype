// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {AlphaHYPEManager02} from "../src/AlphaHYPEManager02.sol";
import {L1Read, L1Write} from "../src/libraries/HcorePrecompiles.sol";
import {MockPrecompiles} from "./MockPrecompiles.t.sol";
import {MockL1Write} from "../src/tests/MockL1Write.sol";

import {console} from "forge-std/console.sol";

contract AlphaHYPEManager02SecurityTest is MockPrecompiles {
    address internal admin;
    address internal executor;
    address internal user;
    address internal validator;

    AlphaHYPEManager02 internal manager;
    AlphaHYPEManager02 internal implementation;

    uint256 constant HYPE_DECIMALS = 10 ** 10; // 18->8 decimals scale

    function setUp() public override {
        super.setUp();

        admin = makeAddr("admin");
        executor = makeAddr("executor");
        user = makeAddr("user");
        validator = makeAddr("validator");

        vm.deal(user, 1000 ether);
        vm.deal(address(this), 1000 ether);

        vm.startPrank(admin);
        implementation = new AlphaHYPEManager02();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), admin, "");
        manager = AlphaHYPEManager02(payable(address(proxy)));
        manager.initialize(validator, 0);
        vm.stopPrank();
    }

    // Helper: user deposit and process to mint aHYPE at 1:1
    function _userDepositAndProcess(address _user, uint256 amount8) internal {
        vm.prank(_user);
        (bool success,) = address(manager).call{value: amount8 * HYPE_DECIMALS}("");
        require(success, "deposit failed");
        vm.stopPrank();
        vm.prank(executor);
        manager.processQueues();
        vm.stopPrank();
        // progress block
        vm.roll(block.number + 1);
    }

    function test_Reentrancy_ClaimCannotDoubleClaim() public {
        // Attacker deposits to get aHYPE
        ReenterOnClaim attacker = new ReenterOnClaim(manager);
        vm.deal(address(attacker), 100 ether);
        _userDepositAndProcess(address(attacker), 100);

        // Fund EVM so owed can be set on withdrawal
        vm.deal(address(manager), 100 * HYPE_DECIMALS);

        // Attacker withdraws all and gets queued owed; process withdrawals directly
        vm.prank(address(attacker));
        manager.withdraw(49);
        manager.processQueues(); // price = 2

        // Reenter claim attempt: inner claim must not pay again
        attacker.setTryReenterClaim(true);
        attacker.initiateClaim();

        vm.expectRevert("AlphaHYPEManager: NO_WITHDRAWAL");
        vm.prank(address(attacker));
        manager.claimWithdrawal();
    }

    function test_Reentrancy_ClaimReentersProcessQueues_StaysSafe() public {
        // Attacker obtains aHYPE and requests withdrawal
        ReenterOnClaim attacker = new ReenterOnClaim(manager);
        vm.deal(address(attacker), 100 ether);
        _userDepositAndProcess(address(attacker), 10);
        vm.prank(address(attacker));
        manager.withdraw(9);
        // Process once to bring money to EVM
        manager.processQueues();  // price = 1
        vm.roll(block.number + 1);
        // Process withdrawal
        manager.processQueues();
        vm.roll(block.number + 1);
        // Attacker will reenter processQueues during claim
        attacker.setTryProcessQueues(true);
        uint256 balBefore = address(attacker).balance;
        attacker.initiateClaim();
        uint256 balAfter = address(attacker).balance;
        vm.roll(block.number + 1);

        // Claimed exactly once
        assertGt(balAfter, balBefore);

        // No aHYPE minted during reentrancy
        assertEq(manager.balanceOf(address(attacker)), 0);

        // Manager still functions after
        vm.prank(executor);
        manager.processQueues();
    }

    function test_NoUnderflow_AfterClaim_ProcessQueuesWorks() public {
        // User gets 100 aHYPE
        _userDepositAndProcess(user, 100);

        // Create EVM liquidity after initial deposit processing (avoid being bridged to spot)
        vm.deal(address(manager), 100 * HYPE_DECIMALS);

        // User withdraws 49 aHYPE
        vm.prank(user);
        manager.withdraw(49);

        // Process withdrawals directly to set owedUnderlyingAmount
        manager.processQueues(); // price = 1
        vm.roll(block.number + 1);
        // Claim the 49 HYPE (reduces both EVM and owedUnderlyingAmount)
        vm.prank(user);
        manager.claimWithdrawal();

        // Should not revert now; invariant holds
        vm.prank(executor);
        manager.processQueues();
    }

    function test_WithdrawRoundingDownAtFractionalPrice() public {
        // User gets 4 aHYPE (5 - fee)
        _userDepositAndProcess(user, 5);
        // Add 3 HYPE on EVM to make price 1.5 (6 underlying / 4 aHYPE)
        vm.deal(address(manager), 3 * HYPE_DECIMALS);
        // Withdraw 3 aHYPE
        vm.prank(user);
        manager.withdraw(3);

        // Process to set owed using floor(3 * 1.5) = 4, -1 fee = 3
        vm.prank(executor);
        manager.processQueues();
        vm.roll(block.number + 1);
        manager.processQueues();
        vm.roll(block.number + 1);
        // User should be able to claim exactly 3 HYPE (8-dec), no rounding up
        uint256 balBefore = user.balance;
        vm.prank(user);
        manager.claimWithdrawal();
        assertEq(user.balance, balBefore + 3 * HYPE_DECIMALS);
    }

    function test_DepositRoundingDownAtFractionalPrice_MintsFloor() public {
        // Setup: create price = 3 HYPE per aHYPE (like existing test)
        _userDepositAndProcess(user, 100); // supply=100, underlying=100

        // Simulate appreciation by adding 200 HYPE on EVM
        vm.deal(address(manager), 200 * HYPE_DECIMALS);

        // New depositor deposits 1 HYPE at price 3 -> mints 0 aHYPE due to floor
        address tiny = makeAddr("tiny");
        vm.deal(tiny, 1 ether);
        vm.prank(tiny);
        (bool ok,) = address(manager).call{value: 1 * HYPE_DECIMALS}("");
        assertTrue(ok);

        vm.prank(executor);
        manager.processQueues();

        assertEq(manager.balanceOf(tiny), 0, "minted amount should floor to 0 at price 3");
    }
}

// Attacker that tries to reenter during claim
contract ReenterOnClaim {
    AlphaHYPEManager02 public manager;
    bool public tryReenterClaim;
    bool public tryProcessQueues;
    bool public triedWithdraw;

    constructor(AlphaHYPEManager02 _manager) {
        manager = _manager;
    }

    function setTryReenterClaim(bool v) external {
        tryReenterClaim = v;
    }

    function setTryProcessQueues(bool v) external {
        tryProcessQueues = v;
    }

    function initiateClaim() external {
        manager.claimWithdrawal();
    }

    // Attempt reentrancy when receiving claim payout
    receive() external payable {
        if (tryReenterClaim) {
            // Low-level call to avoid bubbling revert and failing the whole claim
            address(manager).call(abi.encodeWithSelector(AlphaHYPEManager02.claimWithdrawal.selector));
            tryReenterClaim = false;
        }
        if (tryProcessQueues) {
            // Call nonReentrant-protected external entry (allowed since claim is not nonReentrant)
            // This ensures reentering here doesn't corrupt state.
            tryProcessQueues = false;
            manager.processQueues();
        }
        // Also attempt to add another withdrawal while receiving (should fail due to no balance)
        if (!triedWithdraw) {
            triedWithdraw = true;
            address(manager).call(abi.encodeWithSelector(AlphaHYPEManager02.withdraw.selector, uint256(1)));
        }
    }
}
