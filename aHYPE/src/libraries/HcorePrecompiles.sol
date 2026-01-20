// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";

library L1Read {
    struct Position {
        int64 szi;
        uint64 entryNtl;
        int64 isolatedRawUsd;
        uint32 leverage;
        bool isIsolated;
    }

    struct SpotBalance {
        uint64 total;
        uint64 hold;
        uint64 entryNtl;
    }

    struct UserVaultEquity {
        uint64 equity;
        uint64 lockedUntilTimestamp;
    }

    struct Withdrawable {
        uint64 withdrawable;
    }

    struct Delegation {
        address validator;
        uint64 amount;
        uint64 lockedUntilTimestamp;
    }

    struct DelegatorSummary {
        uint64 delegated;
        uint64 undelegated;
        uint64 totalPendingWithdrawal;
        uint64 nPendingWithdrawals;
    }

    struct PerpAssetInfo {
        string coin;
        uint32 marginTableId;
        uint8 szDecimals;
        uint8 maxLeverage;
        bool onlyIsolated;
    }

    struct SpotInfo {
        string name;
        uint64[2] tokens;
    }

    struct TokenInfo {
        string name;
        uint64[] spots;
        uint64 deployerTradingFeeShare;
        address deployer;
        address evmContract;
        uint8 szDecimals;
        uint8 weiDecimals;
        int8 evmExtraWeiDecimals;
    }

    struct UserBalance {
        address user;
        uint64 balance;
    }

    struct TokenSupply {
        uint64 maxSupply;
        uint64 totalSupply;
        uint64 circulatingSupply;
        uint64 futureEmissions;
        UserBalance[] nonCirculatingUserBalances;
    }

    struct AccountMarginSummary {
        int64 accountValue;
        uint64 marginUsed;
        uint64 ntlPos;
        int64 rawUsd;
    }

    address constant HYPERLIQUIDITY_ADDRESS = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
    address constant POSITION_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000800;
    address constant SPOT_BALANCE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000801;
    address constant VAULT_EQUITY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000802;
    address constant WITHDRAWABLE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000803;
    address constant DELEGATIONS_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000804;
    address constant DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000805;
    address constant MARK_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000806;
    address constant ORACLE_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000807;
    address constant SPOT_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000808;
    address constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;
    address constant PERP_ASSET_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080a;
    address constant SPOT_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080b;
    address constant TOKEN_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080C;
    address constant TOKEN_SUPPLY_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080D;
    address constant ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080F;

    function position(address user, uint16 perp) internal view returns (Position memory) {
        bool success;
        bytes memory result;
        // Left-pad address to 32 bytes for precompile compatibility
        (success, result) = POSITION_PRECOMPILE_ADDRESS.staticcall(abi.encode(uint256(uint160(user)), perp));
        require(success, "Position precompile call failed");
        return abi.decode(result, (Position));
    }

    function spotBalance(address user, uint64 token) internal view returns (SpotBalance memory) {
        bool success;
        bytes memory result;
        // Left-pad address to 32 bytes for precompile compatibility
        (success, result) = SPOT_BALANCE_PRECOMPILE_ADDRESS.staticcall(abi.encode(uint256(uint160(user)), token));
        require(success, "SpotBalance precompile call failed");
        return abi.decode(result, (SpotBalance));
    }

    function userVaultEquity(address user, address vault) internal view returns (UserVaultEquity memory) {
        bool success;
        bytes memory result;
        // Left-pad addresses to 32 bytes for precompile compatibility
        (success, result) =
            VAULT_EQUITY_PRECOMPILE_ADDRESS.staticcall(abi.encode(uint256(uint160(user)), uint256(uint160(vault))));
        require(success, "VaultEquity precompile call failed");
        return abi.decode(result, (UserVaultEquity));
    }

    function withdrawable(address user) internal view returns (Withdrawable memory) {
        bool success;
        bytes memory result;
        // Left-pad address to 32 bytes for precompile compatibility
        (success, result) = WITHDRAWABLE_PRECOMPILE_ADDRESS.staticcall(abi.encode(uint256(uint160(user))));
        require(success, "Withdrawable precompile call failed");
        return abi.decode(result, (Withdrawable));
    }

    function delegations(address user) internal view returns (Delegation[] memory) {
        bool success;
        bytes memory result;
        // Left-pad address to 32 bytes for precompile compatibility
        (success, result) = DELEGATIONS_PRECOMPILE_ADDRESS.staticcall(abi.encode(uint256(uint160(user))));
        require(success, "Delegations precompile call failed");
        return abi.decode(result, (Delegation[]));
    }

    function delegatorSummary(address user) internal view returns (DelegatorSummary memory) {
        bool success;
        bytes memory result;
        // Left-pad address to 32 bytes for precompile compatibility
        (success, result) = DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS.staticcall(abi.encode(uint256(uint160(user))));
        require(success, "DelegatorySummary precompile call failed");
        return abi.decode(result, (DelegatorSummary));
    }

    function markPx(uint32 index) internal view returns (uint64) {
        bool success;
        bytes memory result;
        (success, result) = MARK_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
        require(success, "MarkPx precompile call failed");
        return abi.decode(result, (uint64));
    }

    function oraclePx(uint32 index) internal view returns (uint64) {
        bool success;
        bytes memory result;
        (success, result) = ORACLE_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
        require(success, "OraclePx precompile call failed");
        return abi.decode(result, (uint64));
    }

    function spotPx(uint32 index) internal view returns (uint64) {
        bool success;
        bytes memory result;
        (success, result) = SPOT_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
        require(success, "SpotPx precompile call failed");
        return abi.decode(result, (uint64));
    }

    function l1BlockNumber() internal view returns (uint64) {
        bool success;
        bytes memory result;
        (success, result) = L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS.staticcall(abi.encode());
        console.log("L1BlockNumber precompile call result length:", success);
        require(success, "L1BlockNumber precompile call failed");
        return abi.decode(result, (uint64));
    }

    function perpAssetInfo(uint32 perp) internal view returns (PerpAssetInfo memory) {
        bool success;
        bytes memory result;
        (success, result) = PERP_ASSET_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(perp));
        require(success, "PerpAssetInfo precompile call failed");
        return abi.decode(result, (PerpAssetInfo));
    }

    function spotInfo(uint32 spot) internal view returns (SpotInfo memory) {
        bool success;
        bytes memory result;
        (success, result) = SPOT_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(spot));
        require(success, "SpotInfo precompile call failed");
        return abi.decode(result, (SpotInfo));
    }

    function tokenInfo(uint32 token) internal view returns (TokenInfo memory) {
        bool success;
        bytes memory result;
        (success, result) = TOKEN_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(token));
        require(success, "TokenInfo precompile call failed");
        return abi.decode(result, (TokenInfo));
    }

    function tokenSupply(uint32 token) internal view returns (TokenSupply memory) {
        bool success;
        bytes memory result;
        (success, result) = TOKEN_SUPPLY_PRECOMPILE_ADDRESS.staticcall(abi.encode(token));
        require(success, "TokenSupply precompile call failed");
        return abi.decode(result, (TokenSupply));
    }
}

interface CoreWriter {
    event RawAction(address indexed user, bytes data);

    function sendRawAction(bytes calldata data) external;
}

library L1Write {
    address constant HCORE_PRECOMPILE_ADDRESS = 0x3333333333333333333333333333333333333333;

    uint8 constant FINALIZE_EVM_CONTRACT_Create = 1;
    uint8 constant FINALIZE_EVM_CONTRACT_FirstStorageSlot = 2;
    uint8 constant FINALIZE_EVM_CONTRACT_CustomStorageSlot = 3;

    function tokenDelegate(address validator, uint256 amount, bool isUndelegate) internal {
        bytes memory encodedAction = abi.encode(validator, amount, isUndelegate);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x03;
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        CoreWriter(HCORE_PRECOMPILE_ADDRESS).sendRawAction(data);
    }

    function stakingDeposit(uint64 amount) internal {
        bytes memory encodedAction = abi.encode(amount);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x04;
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        CoreWriter(HCORE_PRECOMPILE_ADDRESS).sendRawAction(data);
    }

    function stakingWithdraw(uint64 amount) internal {
        bytes memory encodedAction = abi.encode(amount);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x05;
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        CoreWriter(HCORE_PRECOMPILE_ADDRESS).sendRawAction(data);
    }

    function spotSend(address destination, uint256 token, uint256 amount) internal {
        bytes memory encodedAction = abi.encode(destination, token, amount);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x06;
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        CoreWriter(HCORE_PRECOMPILE_ADDRESS).sendRawAction(data);
    }

    function sendUsdClassTransfer(uint64 ntl, bool toPerp) internal {
        bytes memory encodedAction = abi.encode(ntl, toPerp);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x07;
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        CoreWriter(HCORE_PRECOMPILE_ADDRESS).sendRawAction(data);
    }

    function finalizeEVMContract(uint64 tokenIndex, uint8 variant, uint64 nonce) internal {
        bytes memory encodedAction = abi.encode(tokenIndex, variant, nonce);
        bytes memory data = new bytes(4 + encodedAction.length);
        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x08;
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        CoreWriter(HCORE_PRECOMPILE_ADDRESS).sendRawAction(data);
    }
}
