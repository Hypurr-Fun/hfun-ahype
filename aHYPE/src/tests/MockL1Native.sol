// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {L1Read} from "../libraries/HcorePrecompiles.sol";
import {console} from "forge-std/console.sol";

interface ISharedL1State {
    function spotBalances(address user, uint64 token)
        external
        view
        returns (uint64 total, uint64 hold, uint64 entryNtl);
    function setSpotBalance(address user, uint64 token, L1Read.SpotBalance memory balance) external;
}

// MockL1Native - to be deployed/pranked at 0x2222222222222222222222222222222222222222
// This contract handles native currency transfers to spot balances
contract MockL1Native {
    ISharedL1State public sharedState;

    event NativeTransferToSpot(address indexed from, uint256 amount);

    constructor(address _sharedState) {
        sharedState = ISharedL1State(_sharedState);
    }

    // Handle native currency transfers
    receive() external payable {
        _handleNativeTransfer(msg.sender, msg.value);
    }

    fallback() external payable {
        _handleNativeTransfer(msg.sender, msg.value);
    }

    function _handleNativeTransfer(address from, uint256 value) internal {
        // Convert wei to 8 decimals (same as contract expects)
        uint64 amount = uint64(value / (10 ** 10));

        // Get current balance for token ID 0 (native currency)
        (uint64 total, uint64 hold, uint64 entryNtl) = sharedState.spotBalances(from, 0);

        console.log("MockL1Native: current balance for", from, total);
        // Update balance
        total += amount;
        console.log("MockL1Native: new balance for", from, total);
        // Create updated balance struct
        L1Read.SpotBalance memory updatedBalance = L1Read.SpotBalance({total: total, hold: hold, entryNtl: entryNtl});

        // Update shared state for token ID 0 (native currency)
        sharedState.setSpotBalance(from, 0, updatedBalance);

        emit NativeTransferToSpot(from, value);
    }

    function setSharedState(address _sharedState) external {
        sharedState = ISharedL1State(_sharedState);
    }
}
