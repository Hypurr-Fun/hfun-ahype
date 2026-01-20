// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {L1Read, L1Write} from "../src/libraries/HcorePrecompiles.sol";

import {MockPosition} from "../src/tests/MockL1Read.sol";
import {MockSpotBalance} from "../src/tests/MockL1Read.sol";
import {MockVaultEquity} from "../src/tests/MockL1Read.sol";
import {MockWithdrawable} from "../src/tests/MockL1Read.sol";
import {MockDelegations} from "../src/tests/MockL1Read.sol";
import {MockDelegatorSummary} from "../src/tests/MockL1Read.sol";
import {MockMarkPx} from "../src/tests/MockL1Read.sol";
import {MockOraclePx} from "../src/tests/MockL1Read.sol";
import {MockSpotPx} from "../src/tests/MockL1Read.sol";
import {MockL1BlockNumber} from "../src/tests/MockL1Read.sol";
import {MockPerpAssetInfo} from "../src/tests/MockL1Read.sol";
import {MockSpotInfo} from "../src/tests/MockL1Read.sol";
import {MockTokenInfo} from "../src/tests/MockL1Read.sol";
import {MockTokenSupply} from "../src/tests/MockL1Read.sol";
import {MockCoreWriter} from "../src/tests/MockL1Read.sol";
import {MockL1Write} from "../src/tests/MockL1Write.sol";
import {MockL1Native} from "../src/tests/MockL1Native.sol";

contract MockPrecompiles is Test {
    MockL1Write public mockL1Write;
    MockL1Native public mockL1Native;
    MockSpotBalance public mockSpotBalance;

    function setUp() public virtual {
        // Deploy shared state contract (MockL1Write) and etch it at 0x3333...
        mockL1Write = new MockL1Write();
        vm.etch(address(0x3333333333333333333333333333333333333333), address(mockL1Write).code);

        // Deploy MockL1Native with the correct shared state address
        mockL1Native = new MockL1Native(address(0x3333333333333333333333333333333333333333));
        mockSpotBalance = new MockSpotBalance(address(0x3333333333333333333333333333333333333333));

        // Etch the contracts at their designated addresses
        vm.etch(address(0x2222222222222222222222222222222222222222), address(mockL1Native).code);
        vm.etch(address(0x0801), address(mockSpotBalance).code);

        // Store the sharedState address in storage slot 0 for both contracts
        vm.store(
            address(0x2222222222222222222222222222222222222222),
            bytes32(uint256(0)),
            bytes32(uint256(uint160(address(0x3333333333333333333333333333333333333333))))
        );
        vm.store(
            address(0x0801),
            bytes32(uint256(0)),
            bytes32(uint256(uint160(address(0x3333333333333333333333333333333333333333))))
        );

        // Deploy other mock precompiles (these don't need shared state)
        vm.etch(address(0x0800), address(new MockPosition()).code);
        vm.etch(address(0x0802), address(new MockVaultEquity()).code);
        vm.etch(address(0x0803), address(new MockWithdrawable()).code);
        vm.etch(address(0x0804), address(new MockDelegations()).code);
        vm.etch(address(0x0805), address(new MockDelegatorSummary()).code);
        MockDelegatorSummary(address(0x0805)).setSharedState(address(0x3333333333333333333333333333333333333333));
        vm.etch(address(0x0806), address(new MockMarkPx()).code);
        vm.etch(address(0x0807), address(new MockOraclePx()).code);
        vm.etch(address(0x0808), address(new MockSpotPx()).code);
        vm.etch(address(0x0809), address(new MockL1BlockNumber()).code);
        vm.etch(address(0x080a), address(new MockPerpAssetInfo()).code);
        vm.etch(address(0x080b), address(new MockSpotInfo()).code);
        vm.etch(address(0x080c), address(new MockTokenInfo()).code);
        vm.etch(address(0x080d), address(new MockTokenSupply()).code);
    }

    function test_tokenInfo() public view {
        L1Read.TokenInfo memory info = L1Read.tokenInfo(1);
        assertEq(info.name, "ETH");
    }

    function test_sharedState() public {
        // Test that native transfers update spot balance
        address user = address(0x1234);
        vm.deal(user, 10 ether);

        // Send native currency to 0x2222... to update spot balance
        vm.prank(user);
        //(bool success,) = payable(address(0x2222222222222222222222222222222222222222)).call{value: 1 ether}("");
        //require(success, "Native transfer failed");
        payable(address(0x2222222222222222222222222222222222222222)).call{value:1 ether}("");
        // Check that spot balance was updated
        L1Read.SpotBalance memory bal = L1Read.spotBalance(user, 0);
        assertEq(bal.total, 1 ether / (10 ** 10), "Spot balance should be updated after native transfer");

        // Test staking deposit (using 8 decimal precision)
        vm.prank(user);
        L1Write.stakingDeposit(50000000); // 0.5 * 10^8

        // Check balances after staking
        bal = L1Read.spotBalance(user, 0);
        assertEq(bal.total, 50000000, "Spot balance total should decrease after staking");

        console.log("FETCHing ");
        L1Read.DelegatorSummary memory ds = L1Read.delegatorSummary(user);
        assertEq(ds.undelegated, 50000000, "Staking undelegated should increase after deposit");

        console.log("fetch detelage", bal.total);
        // Test staking withdraw
        vm.prank(user);
        L1Write.stakingWithdraw(25000000); // 0.25 * 10^8

        // Check balances after withdraw
        bal = L1Read.spotBalance(user, 0);
        ds = L1Read.delegatorSummary(user);
        assertEq(bal.total, 50000000, "Spot balance total should stay the same after withdraw");
        assertEq(ds.undelegated, 25000000, "Staking undelegated should decrease after withdraw");
        assertEq(ds.totalPendingWithdrawal, 25000000, "Total pending withdrawal should increase after withdraw");
    }

    function test_allPrecompiles() public view {
        // Test Position
        L1Read.Position memory pos = L1Read.position(address(this), 1);
        assertEq(pos.szi, 1);
        assertEq(pos.entryNtl, 100);

        // Test SpotBalance
        L1Read.SpotBalance memory bal = L1Read.spotBalance(address(this), 1);
        assertEq(bal.total, 0);
        assertEq(bal.hold, 0);

        // Test VaultEquity
        L1Read.UserVaultEquity memory equity = L1Read.userVaultEquity(address(this), address(0));
        assertEq(equity.equity, 800);

        // Test Withdrawable
        L1Read.Withdrawable memory withdrawable = L1Read.withdrawable(address(this));
        assertEq(withdrawable.withdrawable, 600);

        // Test Delegations
        L1Read.Delegation[] memory delegations = L1Read.delegations(address(this));
        assertEq(delegations.length, 1);
        assertEq(delegations[0].validator, address(0xdead));

        // Test DelegatorSummary
        L1Read.DelegatorSummary memory summary = L1Read.delegatorSummary(address(this));
        assertEq(summary.delegated, 0);

        // Test MarkPx
        uint64 markPx = L1Read.markPx(1);
        assertEq(markPx, 42000);

        // Test OraclePx
        uint64 oraclePx = L1Read.oraclePx(1);
        assertEq(oraclePx, 43000);

        // Test SpotPx
        uint64 spotPx = L1Read.spotPx(1);
        assertEq(spotPx, 44000);

        // Test L1BlockNumber
        uint64 blockNum = L1Read.l1BlockNumber();
        assertEq(blockNum, 123456);

        // Test PerpAssetInfo
        L1Read.PerpAssetInfo memory perpInfo = L1Read.perpAssetInfo(1);
        assertEq(perpInfo.coin, "ETH");
        assertEq(perpInfo.szDecimals, 8);

        // Test SpotInfo
        L1Read.SpotInfo memory spotInfo = L1Read.spotInfo(1);
        assertEq(spotInfo.name, "ETH/USD");
        assertEq(spotInfo.tokens[0], 1);
        assertEq(spotInfo.tokens[1], 2);

        // Test TokenSupply
        L1Read.TokenSupply memory supply = L1Read.tokenSupply(1);
        assertEq(supply.maxSupply, 1000000);
        assertEq(supply.totalSupply, 800000);
    }
}
