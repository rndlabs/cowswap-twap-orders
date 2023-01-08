// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";

import {Tokens} from "./helpers/Tokens.sol";
import {CoWProtocol} from "./helpers/CoWProtocol.sol";
import {Safe} from "./helpers/Safe.sol";

abstract contract Base is Test, Tokens, Safe, CoWProtocol {
    // --- accounts
    address alice;
    uint256 aliceKey;
    address bob;
    uint256 bobKey;
    address carol;
    uint256 carolKey;

    function setUp() public override(CoWProtocol) virtual {
        // setup CoWProtocol
        super.setUp();
        
        // setup test accounts
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        (carol, carolKey) = makeAddrAndKey("carol");

        // give some tokens to alice and bob
        deal(address(token0), alice, 1000e18);
        deal(address(token1), bob, 1000e18);
    }

    function tightlyPackSignature(
        bytes32 r,
        bytes32 s,
        uint8 v
    ) internal pure returns (bytes memory) {
        bytes memory signature = new bytes(65);
        signature = abi.encodePacked(r, s, v);
        return signature;
    }

}