// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AlphaHYPEManager02} from "../src/AlphaHYPEManager02.sol";
import {L1Read, L1Write} from "../src/libraries/HcorePrecompiles.sol";
import {MockPrecompiles} from "./MockPrecompiles.t.sol";
import {MockL1Write} from "../src/tests/MockL1Write.sol";
import {MockDelegatorSummary} from "../src/tests/MockL1Read.sol";


contract AlphaHYPEManager02Test is MockPrecompiles {
    address internal admin;
    address internal executor;
    uint256 internal executorPk;
    address internal user1;
    address internal user2;
    address internal user3;
    address internal validator;

    AlphaHYPEManager02 internal manager;
    AlphaHYPEManager02 internal implementation;

    uint256 constant HYPE_DECIMALS = 10 ** 10; // Converting between 18 decimals (wei) and 8 decimals
    uint256 constant INITIAL_DEPOSIT = 100 * HYPE_DECIMALS; // 100 HYPE in wei
    address constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;
    uint256 constant BPS_DENOMINATOR = 10_000; // 100% = 10_000 bps
    uint256 constant FEE_BPS = 10; // 0.1%

    event DepositRequested(address indexed depositor, uint256 amount);
    event DepositProcessed(address indexed depositor, uint256 hypeAmount, uint256 wrappedAmount);
    event WithdrawalRequested(address indexed withdrawer, uint256 wrappedAmount);
    event WithdrawalProcessed(address indexed withdrawer, uint256 hypeAmount, uint256 wrappedAmount);

    function setUp() public override {
        super.setUp();

        // Setup accounts
        admin = makeAddr("admin");
        (executor, executorPk) = makeAddrAndKey("executor");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        validator = makeAddr("validator");

        // Give users some ETH for testing
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        vm.deal(user3, 1000 ether);
        vm.deal(executor, 100 ether);

        vm.startPrank(admin);

        // 1. Deploy implementation
        implementation = new AlphaHYPEManager02();

        // 2. Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            "" // no initialization data here
        );

        // 3. Cast proxy to AlphaHYPEManager02Harness type
        manager = AlphaHYPEManager02(payable(address(proxy)));

        // 4. Initialize the proxy
        manager.initialize(validator, 0);

        vm.stopPrank();
    }

    // ============ Initialization Tests ============

    function test_InitialState() public view {
        assertEq(manager.name(), "Alpha HYPE");
        assertEq(manager.symbol(), unicode"αHYPE");
        assertEq(manager.decimals(), 8);
        assertEq(manager.totalSupply(), 0);
        assertEq(manager.validator(), validator);
        assertEq(manager.owner(), admin);
        assertEq(manager.withdrawalAmount(), 0);
    }

    // Reverts if validator is zero address
    function test_InitializeRevertsOnZeroValidator() public {
        AlphaHYPEManager02 newImpl = new AlphaHYPEManager02();
        TransparentUpgradeableProxy newProxy = new TransparentUpgradeableProxy(address(newImpl), admin, "");
        AlphaHYPEManager02 newManager = AlphaHYPEManager02(payable(address(newProxy)));

        vm.expectRevert("AlphaHYPEManager: ZERO_ADDRESS");
        newManager.initialize(address(0), 0);
    }

    // Reverts if initialize is called again
    function test_InitializeCanOnlyBeCalledOnce() public {
        vm.expectRevert();
        manager.initialize(validator, 0);
    }

    // ============ Deposit Tests ============

    // Check if depositor is added to queue via receive()
    function test_DepositViaReceive() public {
        uint256 depositAmount = 100 * HYPE_DECIMALS;

        // User deposits 100 * 10^10 wei = 1e-06 HYPE
        // User should be getting 1e-06 aHYPE (8 decimals)
        vm.prank(user1);
        (bool success,) = address(manager).call{value: depositAmount}("");
        assertTrue(success);

        // Check deposit queue
        (address depositor, uint256 amount) = manager.depositQueue(0);
        assertEq(depositor, user1);
        assertEq(amount, 100); // 1e-06 in 8 decimals
    }

    // Check if depositor is added to queue via fallback()
    function test_DepositViaFallback() public {
        uint256 depositAmount = 50 * HYPE_DECIMALS;

        vm.prank(user1);
        (bool success,) = address(manager).call{value: depositAmount}(hex"1234");
        assertTrue(success);

        (address depositor, uint256 amount) = manager.depositQueue(0);
        assertEq(depositor, user1);
        assertEq(amount, 50);
    }

    // Reverts if deposit amount is not round
    function test_DepositRevertsOnInvalidAmount() public {
        // Try to deposit amount that doesn't round to 8 decimals
        uint256 invalidAmount = 100 * HYPE_DECIMALS + 1;

        vm.prank(user1);
        (bool success,) = address(manager).call{value: invalidAmount}("");
        assertFalse(success, "Should revert on invalid amount");
    }

    function test_MultipleDeposits() public {
        // User1 deposits
        vm.prank(user1);
        (bool success1,) = address(manager).call{value: 100 * HYPE_DECIMALS}("");
        assertTrue(success1);

        // User2 deposits
        vm.prank(user2);
        (bool success2,) = address(manager).call{value: 200 * HYPE_DECIMALS}("");
        assertTrue(success2);

        // Check queue
        (address depositor1, uint256 amount1) = manager.depositQueue(0);
        assertEq(depositor1, user1);
        assertEq(amount1, 100);

        (address depositor2, uint256 amount2) = manager.depositQueue(1);
        assertEq(depositor2, user2);
        assertEq(amount2, 200);
    }

    // ============ Withdrawal Tests ============

    function test_WithdrawRequest() public {
        // Setup: First deposit and process to get aHYPE tokens
        _setupUserWithBalance(user1, 100);

        uint256 withdrawAmount = 50;

        vm.prank(user1);
        manager.withdraw(withdrawAmount);

        // Check withdrawal queue
        (address withdrawer, uint256 amount, ) = manager.pendingWithdrawalQueue(0);
        assertEq(withdrawer, user1);
        assertEq(amount, withdrawAmount);
        assertEq(manager.withdrawalAmount(), withdrawAmount);
    }

    function test_WithdrawRevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("AlphaHYPEManager: INVALID_AMOUNT");
        manager.withdraw(0);
    }

    function test_WithdrawRevertsOnInsufficientBalance() public {
        _userDepositAndProcess(user1, 100);

        vm.prank(user1);
        vm.expectRevert("AlphaHYPEManager: INSUFFICIENT_BALANCE");
        manager.withdraw(101);
    }

    function test_MultipleWithdrawals() public {
        _userDepositAndProcess(user1, 100);
        _userDepositAndProcess(user2, 200);

        vm.prank(user1);
        manager.withdraw(50);

        vm.prank(user2);
        manager.withdraw(100);

        assertEq(manager.withdrawalAmount(), 150);

        (address withdrawer1, uint256 amount1, ) = manager.pendingWithdrawalQueue(0);
        assertEq(withdrawer1, user1);
        assertEq(amount1, 50);

        (address withdrawer2, uint256 amount2, ) = manager.pendingWithdrawalQueue(1);
        assertEq(withdrawer2, user2);
        assertEq(amount2, 100);
    }

    // ============ Queue Processing Tests ============

    function test_ProcessDepositsInitialPrice() public {
        // Make deposits
        vm.prank(user1);
        (bool success,) = address(manager).call{value: 100 * HYPE_DECIMALS}("");
        assertTrue(success);

        // Setup minimal spot balance to avoid staking errors
        _setupManagerSpotBalance(0);

        // Process queues
        vm.prank(executor);
        manager.processQueues();

        // Check user received aHYPE at 1:1 ratio (initial price)
        assertEq(manager.balanceOf(user1), 99);
        assertEq(manager.totalSupply(), 99);
    }

    function test_ProcessDepositsWithExistingSupply() public {
        // Setup initial supply
        _setupUserWithBalance(user1, 100);

        // Simulate appreciation by adding HYPE to contract
        vm.deal(address(manager), 200 * HYPE_DECIMALS);

        // User2 deposits 100 HYPE
        vm.prank(user2);
        (bool success,) = address(manager).call{value: 100 * HYPE_DECIMALS}("");
        assertTrue(success);

        // Process queues - price should be 300 HYPE / 100 aHYPE = 3 HYPE per aHYPE
        vm.prank(executor);
        manager.processQueues();

        // User2 should receive 33 aHYPE (100 HYPE / 3) - 1 fee
        assertEq(manager.balanceOf(user2), 32);
        assertEq(manager.totalSupply(), 131);
    }

    function test_ProcessWithdrawalsWithSufficientBalance() public {
        // Setup users with balances
        _userDepositAndProcess(user1, 100);
        _userDepositAndProcess(user2, 100);

        // Request withdrawals
        vm.prank(user1);
        manager.withdraw(49);

        vm.prank(user2);
        manager.withdraw(49);

        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;

        // Process withdrawals
        vm.prank(executor);
        manager.processQueues();
        vm.roll(block.number + 1);
        manager.processQueues();
        vm.roll(block.number + 1);

        vm.prank(user1);
        manager.claimWithdrawal();
        vm.prank(user2);
        manager.claimWithdrawal();
        // Check users received HYPE
        assertGt(user1.balance, user1BalanceBefore);
        assertGt(user2.balance, user2BalanceBefore);

        // Check withdrawal queue is empty
        vm.expectRevert();
        manager.pendingWithdrawalQueue(0);
    }

    function test_ProcessPartialWithdrawals() public {
        // First process should send the hype to spot
        _assertManagerBalance(0, 0, 0, 0, 0);
        _userDepositAndProcess(user1, 100);
        _assertManagerBalance(1, 99, 0, 0, 0);
        _userDepositAndProcess(user2, 100);
        _assertManagerBalance(2, 99, 99, 0, 0);
        // At this point, we should have 100 in spot and 100 in staking

        // Request withdrawals
        vm.prank(user1);
        manager.withdraw(60);
        vm.prank(user2);
        manager.withdraw(50);

        uint256 user1BalanceBefore = user1.balance;

        // Process withdrawals
        vm.prank(executor);
        // no withdrawal should go through
        manager.processQueues();
        vm.roll(block.number + 1);
        // Manager should leave 88 in staking, and withdraw 11 from staking
        _assertManagerBalance(101, 0, 88, 0, 11);

        (address withdrawer1, uint256 amount1,) = manager.pendingWithdrawalQueue(0);
        assertEq(withdrawer1, user1);
        assertEq(amount1, 60);

        (address withdrawer2, uint256 amount2,) = manager.pendingWithdrawalQueue(1);
        assertEq(withdrawer2, user2);
        assertEq(amount2, 50);

        manager.processQueues();
        vm.roll(block.number + 1);
        vm.prank(user1);
        manager.claimWithdrawal();
        vm.stopPrank();
        // 40 is left in EVM, which can't cover the remaining 50 pending withdrawal, and we should be withdrawing 10
        // to match it
        _assertManagerBalance(42, 0, 88, 0, 11);

        (withdrawer1, amount1, ) = manager.pendingWithdrawalQueue(0);
        assertEq(withdrawer1, user2);
        assertEq(amount1, 50);

        vm.expectRevert();
        manager.pendingWithdrawalQueue(1);
    }

    // ============ Staking Integration Tests ============

    function test_StakingDepositWhenNoWithdrawals() public {
        // Setup spot balance for manager
        _setupManagerSpotBalance(1000);

        // Process queues - should stake all HYPE
        vm.prank(executor);
        manager.processQueues();

        // Verify staking deposit was called (check via mock state)
        MockL1Write mockWrite = MockL1Write(address(0x3333333333333333333333333333333333333333));
        assertEq(mockWrite.getStakingBalance(address(manager)).undelegated, 1000);
    }

    function test_NativeTransferToStakingAddress() public {
        // Give the manager contract some native HYPE
        vm.deal(address(manager), 100 * HYPE_DECIMALS);

        // Process queues - should send native HYPE to staking address
        vm.prank(executor);
        manager.processQueues();

        // Check that the native HYPE was sent to the staking address
        // The MockL1Native contract should have updated the spot balance
        MockL1Write mockWrite = MockL1Write(address(0x3333333333333333333333333333333333333333));
        L1Read.SpotBalance memory spotBal = mockWrite.getSpotBalance(address(manager), 0);
        assertEq(spotBal.total, 100, "Manager should have 100 HYPE in spot balance after native transfer");
    }

    function test_DelegationWhenNoWithdrawals() public {
        // Setup undelegated balance
        _setupManagerDelegatorBalance(0, 500, 0, 0);

        // Process queues - should delegate all undelegated HYPE
        vm.prank(executor);
        manager.processQueues();

        // Note: We can't easily verify delegation was called without modifying mocks
        // This test verifies that the function runs without errors
    }

    function test_UndelegationForWithdrawals() public {
        _userDepositAndProcess(user1, 101);

        // Setup delegated balance
        _setupManagerDelegatorBalance(100, 0, 0, 0);

        // Request withdrawal
        vm.prank(user1);
        manager.withdraw(100);

        // Process - should undelegate for withdrawal
        vm.prank(executor);
        vm.expectEmit(true, true, false, true);
        emit AlphaHYPEManager02.TokenDelegate(validator, 100, true);
        manager.processQueues();
    }

    function test_SpotToEVMBridgeForWithdrawals() public {
        _setupUserWithBalance(user1, 100);

        // Setup spot balance
        _setupManagerSpotBalance(200);

        // Request withdrawal
        vm.prank(user1);
        // 100 - mint fee
        manager.withdraw(99);

        // Process - should bridge from spot to EVM
        vm.prank(executor);
        vm.expectEmit(true, true, false, false);
        emit MockL1Write.SpotSend(address(manager), address(0x2222222222222222222222222222222222222222), 0, 100);
        manager.processQueues();
    }

    // ============ Edge Cases and Security Tests ============

    function test_ReentrancyProtection() public {
        ReentrantAttacker attacker = new ReentrantAttacker(manager);
        vm.deal(address(attacker), 100 * HYPE_DECIMALS);

        // User deposit
        _userDepositAndProcess(user1, 100);
        // Attacker deposit
        attacker.deposit();
        vm.prank(executor);
        manager.processQueues();
        vm.roll(block.number + 1);
        // TODO
        // Try reentrancy attack
        //vm.expectRevert();
        // Idea is the smart contract will try to call withdraw again during the first withdraw
        attacker.attack();
        manager.processQueues();
        vm.roll(block.number + 1);
        manager.processQueues();
        vm.roll(block.number + 1);
    }

    function test_RoundingPrevention() public {
        // Try various amounts that might cause rounding issues
        uint256[] memory invalidAmounts = new uint256[](3);
        invalidAmounts[0] = HYPE_DECIMALS - 1;
        invalidAmounts[1] = HYPE_DECIMALS + 1;
        invalidAmounts[2] = 123456789; // Random non-multiple

        for (uint256 i = 0; i < invalidAmounts.length; i++) {
            vm.prank(user1);
            (bool success,) = address(manager).call{value: invalidAmounts[i]}("");
            assertFalse(success, "Should revert on invalid amount");
        }
    }

    function test_OwnershipAccess() public {
        // Non-owner should not be able to call owner functions
        vm.prank(user1);
        vm.expectRevert();
        manager.transferOwnership(user2);

        // Owner should be able to transfer ownership
        vm.prank(admin);
        manager.transferOwnership(user2);
        assertEq(manager.owner(), user2);
    }

    // ============ Complex Integration Tests ============

    function test_MultiUserDepositWithdrawCycle() public {
        // Multiple users deposit
        vm.prank(user1);
        (bool s1,) = address(manager).call{value: 100 * HYPE_DECIMALS}("");
        assertTrue(s1);

        vm.prank(user2);
        (bool s2,) = address(manager).call{value: 200 * HYPE_DECIMALS}("");
        assertTrue(s2);

        // Process deposits
        vm.prank(executor);
        manager.processQueues();
        vm.roll(block.number + 1);

        assertEq(manager.balanceOf(user1), 99);
        assertEq(manager.balanceOf(user2), 199);

        // Add more HYPE to simulate staking rewards
        //vm.deal(address(manager), 600 * HYPE_DECIMALS); // 2x appreciation

        console.log("withdrawing user deposits");
        // Users withdraw half their balances
        vm.prank(user1);
        manager.withdraw(50);

        vm.prank(user2);
        manager.withdraw(100);

        // Process withdrawals
        vm.prank(executor);
        manager.processQueues();
        vm.roll(block.number + 1);
        // Check remaining balances
        assertEq(manager.balanceOf(user1), 49);
        assertEq(manager.balanceOf(user2), 99);
    }

    function test_PriceCalculationWithMixedBalances() public {
        // Setup existing supply
        _setupUserWithBalance(user1, 300);

        // User1 has 300 aHYPE

        // Setup complex balance scenario
        _setupManagerSpotBalance(100);
        _setupManagerDelegatorBalance(200, 50, 25, 1);
        vm.deal(address(manager), 75 * HYPE_DECIMALS);

        // Total underlying = 75 (EVM) + 100 (spot) + 200 (delegated) + 50 (undelegated) + 25 (pending) = 450


        // User2 deposits 150 HYPE
        vm.prank(user2);
        (bool success,) = address(manager).call{value: 150 * HYPE_DECIMALS}("");
        assertTrue(success);

        // Process - price should be 450 HYPE / 300 aHYPE = 1.5 HYPE per aHYPE
        vm.prank(executor);
        manager.processQueues();

        // User2 should receive 100 aHYPE (150 / 1.5) - fee
        assertEq(manager.balanceOf(user2), 99);
    }

    function test_WithdrawalAfterSlash() public {
        // User deposits 100
        _userDepositAndProcess(user1, 101);
        // Price is 1:1
        assertEq(manager.balanceOf(user1), 100);
        // User withdraws 100
        vm.prank(user1);
        manager.withdraw(100);
        // Process withdrawals
        vm.prank(executor);
        manager.processQueues();
        require(manager.owedUnderlyingAmounts(user1) == 0, "invalid owed underlying amount");
        vm.roll(block.number + 1);
        // Slash validator by 50%
        vm.deal(address(manager), 50 * HYPE_DECIMALS);
        manager.processQueues();
        require(manager.owedUnderlyingAmounts(user1) == 48, "invalid owed underlying amount");
    }

    function test_StakingPriorityOrder() public {
        _setupUserWithBalance(user1, 101);

        assertEq(user1.balance, 1000 ether - 101 * (1e10), "invalid user balance after deposit");
        // Check user has 100 aHYPE
        assertEq(manager.balanceOf(user1), 100);

        // Setup various balances
        _setupManagerSpotBalance(200);
        _setupManagerDelegatorBalance(300, 100, 100, 1);

        // aHYPE underlying = 700, supply = 100
        // aHYPE price = 7 HYPE

        // Request withdrawal of all user holding.
        vm.prank(user1);
        manager.withdraw(100);

        vm.prank(executor);
        // Expect manager to
        // - call SpotToEVMBridge event with spot balance (200)
        // - call StakingWithdraw with undelegated balance (100)
        // - call undelegate with remaining needed (300)
        // Total: 200 + 100 (pending) + 100 + 300 = 700 HYPE needed
        vm.expectEmit(true, true, false, true);
        emit AlphaHYPEManager02.SpotSend(200, HYPE_SYSTEM_ADDRESS);
        vm.expectEmit(true, true, false, true);
        emit AlphaHYPEManager02.StakingWithdraw(100);
        vm.expectEmit(true, true, true, true);
        emit AlphaHYPEManager02.TokenDelegate(validator, 300, true);
        manager.processQueues();
        vm.roll(block.number + 1);

        // The withdrawal is still in queue because funds weren't available during withdrawal processing
        // (spot-to-EVM bridge happens AFTER withdrawal processing in the same call)
        (address withdrawer1, uint256 amount1, ) = manager.pendingWithdrawalQueue(0);
        assertEq(withdrawer1, user1);
        assertEq(amount1, 100);

        // Now the manager should have 200 HYPE in EVM balance from the bridge
        _assertManagerBalance(201, 0, 300, 0, 200);

        // Process again to actually handle the withdrawal with available funds
        vm.prank(executor);
        // We expecit a withdraw from staking from the previous undelegation
        vm.expectEmit(true, true, false, true);
        emit AlphaHYPEManager02.StakingWithdraw(300);
        manager.processQueues();
        vm.roll(block.number + 1);

        // The manager should now have 200 in EVM, 0 in spot, 0 undelegated, 0 delegated, and 500 pending withdrawal
        _assertManagerBalance(201, 0, 0, 0, 500);
        // Withdrawal still stuck
        (withdrawer1, amount1,) = manager.pendingWithdrawalQueue(0);
        assertEq(withdrawer1, user1);
        assertEq(amount1, 100);

        _clearPendingWithdrawals();
        _assertManagerBalance(201, 500, 0, 0, 0);

        // The manager should move the new spot balance to evm
        vm.expectEmit(true, true, false, true);
        emit AlphaHYPEManager02.SpotSend(500, HYPE_SYSTEM_ADDRESS);
        manager.processQueues();
        vm.roll(block.number + 1);

        _assertManagerBalance(701, 0, 0, 0, 0);

        // Withdrawal still stuck
        (withdrawer1, amount1,) = manager.pendingWithdrawalQueue(0);
        assertEq(withdrawer1, user1);
        assertEq(amount1, 100);

        // Now the withdrawal should be processed
        manager.processQueues();
        vm.roll(block.number + 1);

        // No claim so still the same
        _assertManagerBalance(701, 0, 0, 0, 0);

        vm.prank(user1);
        manager.claimWithdrawal();
        // User should have received their HYPE
        assertEq(user1.balance, 1000 ether + (600 - 2) * (1e10), "invalid user balance after withdrawal");
        vm.expectRevert();
        manager.pendingWithdrawalQueue(0);
    }

    // ============ Helper Functions ============

    function _assertManagerBalance(uint256 evm, uint256 spot, uint256 undelegated, uint256 delegated, uint256 pending) internal {
        assertEq(address(manager).balance, evm * HYPE_DECIMALS, "evm balance mismatch");
        L1Read.SpotBalance memory sb = L1Read.spotBalance(address(manager), 0);
        assertEq(sb.total, spot, "spot total mismatch");
        L1Read.DelegatorSummary memory ds = L1Read.delegatorSummary(address(manager));
        assertEq(ds.undelegated, undelegated, "undelegated mismatch");
        assertEq(ds.delegated, delegated, "delegated mismatch");
        assertEq(ds.totalPendingWithdrawal, pending, "pending mismatch");
    }

    function _userDepositAndProcess(address user, uint256 amount) internal {
        // Make deposit from user
        vm.prank(user);
        (bool success,) = address(manager).call{value: amount * HYPE_DECIMALS}("");
        require(success, "Deposit failed");

        // Process the deposit queue
        vm.prank(executor);
        vm.expectEmit(true, true, false, true);
        uint256 mintFee = Math.mulDiv(amount, FEE_BPS, BPS_DENOMINATOR, Math.Rounding.Ceil);
        emit AlphaHYPEManager02.EVMSend(amount - mintFee, HYPE_SYSTEM_ADDRESS);
        manager.processQueues();
        vm.roll(block.number + 1);
    }

    function _setupUserWithBalance(address user, uint256 amount) internal {
        // Make deposit from user
        vm.prank(user);
        (bool success,) = address(manager).call{value: amount * HYPE_DECIMALS}("");
        require(success, "Deposit failed");

        // Process the deposit queue
        vm.prank(executor);
        manager.processQueues();
        vm.roll(block.number + 1);
    }

    function _setupManagerSpotBalance(uint64 balance) internal {
        L1Read.SpotBalance memory spotBal = L1Read.SpotBalance({total: balance, hold: 0, entryNtl: 0});

        MockL1Write(address(0x3333333333333333333333333333333333333333)).setSpotBalance(address(manager), 0, spotBal);
    }

    function _setupManagerDelegatorBalance(
        uint64 delegated,
        uint64 undelegated,
        uint64 pendingWithdrawal,
        uint64 nPendingWithdrawal
    ) internal {
        L1Read.DelegatorSummary memory delSummary = L1Read.DelegatorSummary({
            delegated: delegated,
            undelegated: undelegated,
            totalPendingWithdrawal: pendingWithdrawal,
            nPendingWithdrawals: nPendingWithdrawal
        });
        MockL1Write(address(0x3333333333333333333333333333333333333333)).setStakingBalance(address(manager), delSummary);
    }

    function _clearPendingWithdrawals() internal {
        // Clear pending withdrawals by setting to zero
        MockL1Write(address(0x3333333333333333333333333333333333333333)).clearPendingWithdrawals(address(manager));
    }
}

// Helper contract for testing reentrancy
contract ReentrantAttacker {
    AlphaHYPEManager02 public manager;
    bool public attacking;

    constructor(AlphaHYPEManager02 _manager) {
        manager = _manager;
    }

    function deposit() external {
        (bool success,) = address(manager).call{value: 10 * 10 ** 10}("");
        require(success);
    }

    function attack() external {
        attacking = true;
        manager.withdraw(9);
    }

    receive() external payable {
        if (attacking) {
            attacking = false;
            manager.withdraw(5);
        }
    }
}

// Custom mock for testing specific delegator summary values
contract MockDelegatorSummaryCustom {
    uint64 public delegated;
    uint64 public undelegated;
    uint64 public pendingWithdrawal;

    constructor(uint64 _delegated, uint64 _undelegated, uint64 _pendingWithdrawal) {
        delegated = _delegated;
        undelegated = _undelegated;
        pendingWithdrawal = _pendingWithdrawal;
    }

    fallback() external {
        L1Read.DelegatorSummary memory ds = L1Read.DelegatorSummary({
            delegated: delegated,
            undelegated: undelegated,
            totalPendingWithdrawal: pendingWithdrawal,
            nPendingWithdrawals: pendingWithdrawal > 0 ? 1 : 0
        });

        bytes memory response = abi.encode(ds);
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}
