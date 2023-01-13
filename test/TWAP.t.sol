// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";

import {IERC165} from "safe/interfaces/IERC165.sol";
import {ERC721TokenReceiver} from "safe/interfaces/ERC721TokenReceiver.sol";
import {ERC777TokensRecipient} from "safe/interfaces/ERC777TokensRecipient.sol";
import {ERC1155TokenReceiver} from "safe/interfaces/ERC1155TokenReceiver.sol";
import {GnosisSafe} from "safe/GnosisSafe.sol";
import {Enum} from "safe/common/Enum.sol";

import {GPv2Order} from "cowprotocol/libraries/GPv2Order.sol";

import {ConditionalOrder} from "../src/interfaces/ConditionalOrder.sol";
import {ConditionalOrderLib} from "../src/libraries/ConditionalOrderLib.sol";
import {TWAPOrder} from "../src/libraries/TWAPOrder.sol";
import {CoWTWAPFallbackHandler} from "../src/CoWTWAPFallbackHandler.sol";

import "./Base.t.sol";

contract CoWTWAP is Base {
    using TestAccountLib for TestAccount[];
    using TWAPOrder for TWAPOrder.Data;
    using GPv2Order for GPv2Order.Data;

    event ConditionalOrderCreated(address indexed, bytes);

    CoWTWAPFallbackHandler twapSingleton;
    CoWTWAPFallbackHandler twapSafe;

    function setUp() public override(Base) virtual {
        super.setUp();

        // deploy the CoW TWAP fallback handler
        twapSingleton = new CoWTWAPFallbackHandler(settlement);

        // enable the CoW TWAP fallback handler for safe 1
        _enableTWAP(safe1);
        twapSafe = CoWTWAPFallbackHandler(address(safe1));
    }

    function testCreateTWAP() public {
        // declare the TWAP bundle
        TWAPOrder.Data memory bundle = TWAPOrder.Data({
            token0: token0,
            token1: token1,
            receiver: address(0), // the safe itself
            amount: 1000e18,
            lim: 100e18,
            flags: 0, // sell token0 for token1
            t0: block.timestamp,
            n: 10,
            t: 1 days,
            span: 12 hours
        });
        bytes memory bundleBytes = abi.encode(bundle);

        // 1. create a TWAP order
        bytes32 typedHash = ConditionalOrderLib.hash(bundleBytes, settlement.domainSeparator());

        // this should emit a ConditionalOrderCreated event
        vm.expectEmit(true, true, true, false);
        emit ConditionalOrderCreated(address(twapSafe), bundleBytes);

        // Everything here happens in a batch
        execute(
            GnosisSafe(payable(address(twapSafe))),
            address(multisend),
            0,
            abi.encodeWithSelector(
                multisend.multiSend.selector, 
                abi.encodePacked(
                    // 1. sign the TWAP order
                    abi.encodePacked(
                        uint8(Enum.Operation.DelegateCall),
                        address(signMessageLib),
                        uint256(0),
                        uint256(100), // 4 bytes for the selector + 96 bytes for the typedHash as bytes
                        abi.encodeWithSelector(
                            signMessageLib.signMessage.selector,
                            abi.encode(typedHash)
                        )
                    ),
                    // 2. approve the tokens to be spent by the settlement contract
                    abi.encodePacked(
                        Enum.Operation.Call,
                        address(token0),
                        uint256(0),
                        uint256(68), // 4 bytes for the selector + 32 bytes for the spender + 32 bytes for the amount
                        abi.encodeWithSelector(
                            token0.approve.selector,
                            address(relayer),
                            bundle.amount
                        )
                    ),
                    // 3. dispatch the TWAP order
                    abi.encodePacked(
                        Enum.Operation.Call,
                        address(twapSafe),
                        uint256(0),
                        uint256(388), // 4 bytes for the selector + 384 bytes for the bundle variable length header
                        abi.encodeWithSelector(
                            twapSafe.dispatch.selector,
                            bundleBytes
                        )
                    )
                )
            ),
            Enum.Operation.DelegateCall,
            signers()
        );

        // get a part of the TWAP bundle
        GPv2Order.Data memory order = twapSafe.getTradeableOrder(bundleBytes);
        console.logBytes(abi.encode(order));

        // Test the isValidSignature function
        bytes32 orderDigest = order.hash(settlement.domainSeparator());

        assertTrue(twapSafe.isValidSignature(orderDigest, bundleBytes) == bytes4(0x1626ba7e));

        // fast forward to the end of the span
        vm.warp(block.timestamp + 12 hours + 1 minutes);

        assertTrue(twapSafe.isValidSignature(orderDigest, bundleBytes) != bytes4(0x1626ba7e));
    }

    function testSetCoWTWAPFallbackHandler() public {
        // set the fallback handler to the CoW TWAP fallback handler
        _enableTWAP(safe2);

        // check that the fallback handler is set
        // get the storage at 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5
        // which is the storage slot of the fallback handler
        assertEq(
            vm.load(address(safe2), 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5),
            bytes32(uint256(uint160(address(twapSingleton))))
        );

        // check some of the standard interfaces that the fallback handler supports
        CoWTWAPFallbackHandler _safe = CoWTWAPFallbackHandler(address(safe2));
        assertTrue(_safe.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_safe.supportsInterface(type(ERC721TokenReceiver).interfaceId));
        assertTrue(_safe.supportsInterface(type(ERC1155TokenReceiver).interfaceId));
    }

    function _enableTWAP(GnosisSafe safe) internal {
        // do the transaction
        execute(
            safe,
            address(safe),
            0,
            abi.encodeWithSelector(
                safe.setFallbackHandler.selector,
                address(twapSingleton)
            ),
            Enum.Operation.Call,
            signers()
        );
    }
}