// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {L1Read, CoreWriter} from "../libraries/HcorePrecompiles.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

contract SharedL1State {
    mapping(address => mapping(uint64 => L1Read.SpotBalance)) public spotBalances;
    mapping(address => L1Read.DelegatorSummary) public stakingBalances;

    event SpotBalanceUpdated(address indexed user, uint64 indexed token, uint64 total, uint64 hold, uint64 entryNtl);
    event StakingBalanceUpdated(address indexed user, uint256 balance);

    function setSpotBalance(address user, uint64 token, L1Read.SpotBalance memory balance) public {
        console.log("ShatedL1State:setSpotBalance", user, token, balance.total);
        spotBalances[user][token] = balance;
        emit SpotBalanceUpdated(user, token, balance.total, balance.hold, balance.entryNtl);
    }

    function setStakingBalance(address user, L1Read.DelegatorSummary memory balance) public {
        console.log("ShatedL1State:setStakingBalance", user, balance.delegated);
        stakingBalances[user] = balance;
        emit StakingBalanceUpdated(user, balance.delegated);
    }

    // Helper functions for testing
    function getSpotBalance(address user, uint64 token) external view returns (L1Read.SpotBalance memory) {
        return spotBalances[user][token];
    }

    function getStakingBalance(address user) external view returns (L1Read.DelegatorSummary memory) {
        return stakingBalances[user];
    }

    function clearPendingWithdrawals(address user) external {
        L1Read.DelegatorSummary memory ds = stakingBalances[user];
        L1Read.SpotBalance memory sb = spotBalances[user][0];
        sb.total += ds.totalPendingWithdrawal;
        ds.nPendingWithdrawals = 0;
        ds.totalPendingWithdrawal = 0;
        stakingBalances[user] = ds;
        spotBalances[user][0] = sb;
    }
}

// MockL1Write - to be deployed/pranked at 0x3333333333333333333333333333333333333333
// This contract simulates the L1Write precompile (CoreWriter interface)
contract MockL1Write is SharedL1State, CoreWriter {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    event StakingDeposit(address indexed from, uint64 amount);
    event StakingWithdraw(address indexed from, uint64 amount);
    event TokenDelegate(address indexed from, address indexed validator, uint256 amount, bool isUndelegate);
    event SpotSend(address indexed from, address indexed destination, uint256 token, uint256 amount);
    event UsdClassTransfer(address indexed from, uint64 ntl, bool toPerp);

    // Implement CoreWriter interface
    function sendRawAction(bytes calldata data) external override {
        emit RawAction(msg.sender, data);

        // Parse the action type from the first 4 bytes
        require(data.length >= 4, "Invalid data length");

        uint8 actionType = uint8(data[3]);

        if (actionType == 0x03) {
            // Token delegate/undelegate
            _handleTokenDelegate(data[4:]);
        } else if (actionType == 0x04) {
            // Staking deposit
            _handleStakingDeposit(data[4:]);
        } else if (actionType == 0x05) {
            // Staking withdraw
            _handleStakingWithdraw(data[4:]);
        } else if (actionType == 0x06) {
            // Spot send
            _handleSpotSend(data[4:]);
        } else if (actionType == 0x07) {
            // USD class transfer
            _handleUsdClassTransfer(data[4:]);
        }
    }

    function _handleTokenDelegate(bytes calldata encodedAction) internal {
        (address validator, uint256 amount, bool isUndelegate) = abi.decode(encodedAction, (address, uint256, bool));
        require(amount <= type(uint64).max, "Amount exceeds uint64 max");
        uint64 amt64 = uint64(amount);
        L1Read.DelegatorSummary memory ds = stakingBalances[msg.sender];
        if (isUndelegate) {
            require(ds.delegated >= amt64, "Insufficient delegated balance to undelegate");
            ds.delegated -= amt64;
            ds.undelegated += amt64;
        } else {
            require(ds.undelegated >= amt64, "Insufficient undelegated balance to delegate");
            ds.delegated += amt64;
            ds.undelegated -= amt64;
        }
        stakingBalances[msg.sender] = ds;
        emit TokenDelegate(msg.sender, validator, amount, isUndelegate);
    }

    function _handleStakingDeposit(bytes calldata encodedAction) internal {
        uint64 amount = abi.decode(encodedAction, (uint64));

        // Get current balance - use token 0 for native currency
        L1Read.SpotBalance memory balance = spotBalances[msg.sender][0];
        require(balance.total >= amount, "Insufficient spot balance");

        L1Read.DelegatorSummary memory ds = stakingBalances[msg.sender];

        // Update balances
        balance.total -= amount;
        ds.undelegated += amount;
        spotBalances[msg.sender][0] = balance;
        stakingBalances[msg.sender] = ds;

        emit SpotBalanceUpdated(msg.sender, 0, balance.total, balance.hold, balance.entryNtl);
        emit StakingDeposit(msg.sender, amount);
    }

    function _handleStakingWithdraw(bytes calldata encodedAction) internal {
        uint64 amount = abi.decode(encodedAction, (uint64));
        require(stakingBalances[msg.sender].undelegated >= amount, "Insufficient undelegated staking balance");

        L1Read.DelegatorSummary memory ds = stakingBalances[msg.sender];
        ds.undelegated -= amount;
        ds.totalPendingWithdrawal += amount;
        ds.nPendingWithdrawals += 1;

        stakingBalances[msg.sender] = ds;

        emit StakingWithdraw(msg.sender, amount);
    }

    function _handleSpotSend(bytes calldata encodedAction) internal {
        // Decode the actual parameters from L1Write.spotSend
        (address destination, uint256 token, uint256 amount) = abi.decode(encodedAction, (address, uint256, uint256));

        // Update spot balance - simulate transfer from L1 to EVM
        L1Read.SpotBalance memory senderBalance = spotBalances[msg.sender][uint64(token)];
        require(senderBalance.total >= amount, "Insufficient spot balance for send");
        senderBalance.total -= uint64(amount);
        spotBalances[msg.sender][uint64(token)] = senderBalance;

        if (destination == 0x2222222222222222222222222222222222222222) {
            // User sent to EVM (HYPE_SYSTEM_ADDRESS), top up their EVM balance
            // Convert from 8 decimals to 18 decimals (wei)
            uint256 weiAmount = amount * (10 ** 10);
            // call receive
            vm.deal(address(0x2222222222222222222222222222222222222222), weiAmount);
            vm.prank(0x2222222222222222222222222222222222222222);
            (bool success,) = payable(msg.sender).call{value: weiAmount}("");
            require(success, "Failed to send HYPE to EVM");
        } else {
            // For other addresses, just log the event
            L1Read.SpotBalance memory destBalance = spotBalances[destination][uint64(token)];
            destBalance.total += uint64(amount);
            spotBalances[destination][uint64(token)] = destBalance;
        }

        // Emit the event
        emit SpotSend(msg.sender, destination, token, amount);
    }

    function _handleUsdClassTransfer(bytes calldata encodedAction) internal {
        (uint64 ntl, bool toPerp) = abi.decode(encodedAction, (uint64, bool));
        emit UsdClassTransfer(msg.sender, ntl, toPerp);
    }
}
