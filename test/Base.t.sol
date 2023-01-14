// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";

import {Enum} from "safe/common/Enum.sol";
import {GnosisSafe} from "safe/GnosisSafe.sol";

import {ConditionalOrderLib} from "../src/libraries/ConditionalOrderLib.sol";
import {CoWFallbackHandler} from "../src/CoWFallbackHandler.sol";

import {TestAccount, TestAccountLib} from "./libraries/TestAccountLib.sol";
import {IERC20, Tokens} from "./helpers/Tokens.sol";
import {CoWProtocol} from "./helpers/CoWProtocol.sol";
import {Safe} from "./helpers/Safe.sol";

abstract contract Base is Test, Tokens, Safe, CoWProtocol {
    using TestAccountLib for TestAccount[];
    using TestAccountLib for TestAccount;

    // --- accounts
    TestAccount alice;
    TestAccount bob;
    TestAccount carol;

    GnosisSafe public safe1;
    GnosisSafe public safe2;

    function setUp() public override(CoWProtocol) virtual {
        // setup CoWProtocol
        super.setUp();
        
        // setup test accounts
        alice = TestAccountLib.createTestAccount("alice");
        bob = TestAccountLib.createTestAccount("bob");
        carol = TestAccountLib.createTestAccount("carol");

        // give some tokens to alice and bob
        deal(address(token0), alice.addr, 1000e18);
        deal(address(token1), bob.addr, 1000e18);

        // create a safe with alice, bob and carol as owners and a threshold of 2
        address[] memory owners = new address[](3);
        owners[0] = alice.addr;
        owners[1] = bob.addr;
        owners[2] = carol.addr;

        safe1 = GnosisSafe(payable(createSafe(owners, 2, 0)));
        safe2 = GnosisSafe(payable(createSafe(owners, 2, 1)));
    }

    function signers() internal view returns (TestAccount[] memory) {
        TestAccount[] memory signers = new TestAccount[](2);
        signers[0] = alice;
        signers[1] = bob;
        return signers;
    }
}