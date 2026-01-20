// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {L1Read, CoreWriter} from "../libraries/HcorePrecompiles.sol";
import {console} from "forge-std/console.sol";

// 0x0800
contract MockPosition {
    fallback() external {
        L1Read.Position memory p =
            L1Read.Position({szi: 1, entryNtl: 100, isolatedRawUsd: 50, leverage: 10, isIsolated: true});

        bytes memory response = abi.encode(p);
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// Shared state storage contract interface
interface ISharedL1State {
    function spotBalances(address user, uint64 token)
        external
        view
        returns (uint64 total, uint64 hold, uint64 entryNtl);

    function stakingBalances(address user) external view returns (L1Read.DelegatorSummary memory);

    function setSpotBalance(address user, uint64 token, L1Read.SpotBalance memory balance) external;

    function getSpotBalance(address user, uint64 token) external view returns (L1Read.SpotBalance memory);
}

// 0x0801
contract MockSpotBalance {
    ISharedL1State public sharedState;

    constructor(address _sharedState) {
        sharedState = ISharedL1State(_sharedState);
    }

    function setSharedState(address _sharedState) external {
        sharedState = ISharedL1State(_sharedState);
    }

    fallback() external {
        require(address(sharedState) != address(0));

        // Decode left-padded address format
        (uint256 userPadded, uint64 token) = abi.decode(msg.data, (uint256, uint64));
        address user = address(uint160(userPadded));

        L1Read.SpotBalance memory b = sharedState.getSpotBalance(user, token);

        bytes memory response = abi.encode(b);
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x0802
contract MockVaultEquity {
    fallback() external {
        L1Read.UserVaultEquity memory v = L1Read.UserVaultEquity({equity: 800, lockedUntilTimestamp: 1700000000});

        bytes memory response = abi.encode(v);
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x0803
contract MockWithdrawable {
    fallback() external {
        L1Read.Withdrawable memory w = L1Read.Withdrawable({withdrawable: 600});

        bytes memory response = abi.encode(w);
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x0804
contract MockDelegations {
    fallback() external {
        L1Read.Delegation[] memory d = new L1Read.Delegation[](1);
        d[0] = L1Read.Delegation({validator: address(0xdead), amount: 1000, lockedUntilTimestamp: 1800000000});

        bytes memory response = abi.encode(d);
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x0805
contract MockDelegatorSummary {
    ISharedL1State public sharedState;

    function setSharedState(address _sharedState) external {
        sharedState = ISharedL1State(_sharedState);
    }

    fallback() external {
        require(address(sharedState) != address(0), "MockDelegatorSummary: sharedState not set");

        // Decode left-padded address format
        uint256 userPadded = abi.decode(msg.data, (uint256));
        address user = address(uint160(userPadded));

        L1Read.DelegatorSummary memory b = sharedState.stakingBalances(user);

        bytes memory response = abi.encode(b);
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x0806
contract MockMarkPx {
    fallback() external {
        bytes memory response = abi.encode(uint64(42000));
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x0807
contract MockOraclePx {
    fallback() external {
        bytes memory response = abi.encode(uint64(43000));
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x0808
contract MockSpotPx {
    fallback() external {
        bytes memory response = abi.encode(uint64(44000));
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x0809
contract MockL1BlockNumber {
    fallback() external {
        bytes memory response = abi.encode(uint64(123456));
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x080a
contract MockPerpAssetInfo {
    fallback() external {
        L1Read.PerpAssetInfo memory info =
            L1Read.PerpAssetInfo({coin: "ETH", marginTableId: 1, szDecimals: 8, maxLeverage: 50, onlyIsolated: false});

        bytes memory response = abi.encode(info);
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x080b
contract MockSpotInfo {
    fallback() external {
        L1Read.SpotInfo memory info = L1Read.SpotInfo({name: "ETH/USD", tokens: [uint64(1), uint64(2)]});

        bytes memory response = abi.encode(info);
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x080c
contract MockTokenInfo {
    mapping(uint32 => L1Read.TokenInfo) public tokenInfos;

    function setTokenInfo(uint32 tokenIndex, L1Read.TokenInfo memory info) external {
        tokenInfos[tokenIndex] = info;
    }

    fallback() external {
        uint32 tokenIndex = abi.decode(msg.data, (uint32));
        L1Read.TokenInfo memory info = tokenInfos[tokenIndex];

        // Default values if not set
        if (bytes(info.name).length == 0) {
            uint64[] memory spots = new uint64[](2);
            spots[0] = 1;
            spots[1] = 2;

            info = L1Read.TokenInfo({
                name: "ETH",
                spots: spots,
                deployerTradingFeeShare: 100,
                deployer: address(0xbeef),
                evmContract: address(0xcafe),
                szDecimals: 8,
                weiDecimals: 18,
                evmExtraWeiDecimals: 10
            });
        }

        bytes memory response = abi.encode(info);
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

// 0x080d
contract MockTokenSupply {
    struct StoredTokenSupply {
        uint64 maxSupply;
        uint64 totalSupply;
        uint64 circulatingSupply;
        uint64 futureEmissions;
    }

    mapping(uint32 => StoredTokenSupply) public tokenSupplies;

    function setTokenSupply(
        uint32 token,
        uint64 maxSupply,
        uint64 totalSupply,
        uint64 circulatingSupply,
        uint64 futureEmissions
    ) external {
        tokenSupplies[token] = StoredTokenSupply({
            maxSupply: maxSupply,
            totalSupply: totalSupply,
            circulatingSupply: circulatingSupply,
            futureEmissions: futureEmissions
        });
    }

    fallback() external {
        uint32 token = abi.decode(msg.data, (uint32));
        StoredTokenSupply memory stored = tokenSupplies[token];

        L1Read.UserBalance[] memory nonCirc;

        // Default values if not set
        if (stored.maxSupply == 0) {
            nonCirc = new L1Read.UserBalance[](1);
            nonCirc[0] = L1Read.UserBalance({user: address(0xabcd), balance: 100});

            L1Read.TokenSupply memory supply = L1Read.TokenSupply({
                maxSupply: 1000000,
                totalSupply: 800000,
                circulatingSupply: 750000,
                futureEmissions: 50000,
                nonCirculatingUserBalances: nonCirc
            });

            bytes memory response = abi.encode(supply);
            assembly {
                return(add(response, 0x20), mload(response))
            }
        } else {
            nonCirc = new L1Read.UserBalance[](0);

            L1Read.TokenSupply memory supply = L1Read.TokenSupply({
                maxSupply: stored.maxSupply,
                totalSupply: stored.totalSupply,
                circulatingSupply: stored.circulatingSupply,
                futureEmissions: stored.futureEmissions,
                nonCirculatingUserBalances: nonCirc
            });

            bytes memory response = abi.encode(supply);
            assembly {
                return(add(response, 0x20), mload(response))
            }
        }
    }
}

// 0x3333333333333333333333333333333333333333
contract MockCoreWriter is CoreWriter {
    function sendRawAction(bytes calldata data) external override {
        emit RawAction(msg.sender, data);
    }
}
