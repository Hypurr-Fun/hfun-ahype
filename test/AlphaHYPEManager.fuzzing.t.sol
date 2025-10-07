pragma solidity =0.8.26;

import {Test} from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockPrecompiles} from "./MockPrecompiles.t.sol";
import {AlphaHYPEManager02} from "../src/AlphaHYPEManager02.sol";

contract AlphaHypeManagerTest is MockPrecompiles {
    address internal admin;
    address internal executor;
    uint256 internal executorPk;
    address internal user1;
    address internal user2;
    address internal user3;
    address internal validator;

    AlphaHYPEManager02 internal manager;

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
        AlphaHYPEManager02 implementation = new AlphaHYPEManager02();

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

        Fuzzer fuzzer = new Fuzzer(payable(address(manager)));

        // Set up invariant testing for factory
        targetContract(address(fuzzer));
    }

    // Invariant: supply should always match if no rewards are given or slashing happens
    function invariant_Supply() public {
       // Underlying and ERC20 have to match all the time
        assertEq(manager.getERC20Supply(), manager.getUnderlyingSupply(), "ERC20 and underlying supply mismatch");
    }

    // Invariant: hype balance is always divisible by 1e10
    function invariant_HypeBalance() public {
        assertEq(address(manager).balance % 1e10, 0, "Hype balance not multiple of 1e10");
    }

    function invariant_VirtualWithdrawalAmount() public {
        if (manager.pendingWithdrawalQueueLength() == 0) {
            assertEq(manager.virtualWithdrawalAmount(), 0, "Virtual withdrawal amount mismatch");
            assertEq(manager.withdrawalAmount(), 0, "Withdrawal amount mismatch");
        }
    }
}


contract Fuzzer is Test {
    mapping(address => uint256) public ks;

    AlphaHYPEManager02 internal manager;

    constructor(address payable _manager) {
        manager = AlphaHYPEManager02(payable(_manager));
    }

    function deposit(uint256 amount) public {
        // make sure multiple of 1e10
        vm.deal(address(this), amount * 1e10);
        (bool success,) = address(manager).call{value: amount * 1e10}("");
        require(success, "Deposit failed");
    }

    function withdraw(uint256 amount) public {
        manager.withdraw(amount);
    }

    function processQueues() public {
        manager.processQueues();
    }

    function claimWithdrawal() public {
        manager.claimWithdrawal();
    }
}