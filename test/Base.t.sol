// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";

import "./libraries/TestAccountLib.sol";

import {Tokens} from "./helpers/Tokens.sol";
import {CoWProtocol} from "./helpers/CoWProtocol.sol";
import {Safe} from "./helpers/Safe.sol";

abstract contract Base is Test, Tokens, Safe, CoWProtocol {
    using TestAccountLib for TestAccount[];
    using TestAccountLib for TestAccount;

    // --- accounts
    TestAccount alice;
    TestAccount bob;
    TestAccount carol;

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
    }
}