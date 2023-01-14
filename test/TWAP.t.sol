// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC165} from "safe/interfaces/IERC165.sol";
import {ERC721TokenReceiver} from "safe/interfaces/ERC721TokenReceiver.sol";
import {ERC777TokensRecipient} from "safe/interfaces/ERC777TokensRecipient.sol";
import {ERC1155TokenReceiver} from "safe/interfaces/ERC1155TokenReceiver.sol";
import {GnosisSafe} from "safe/GnosisSafe.sol";

import {GPv2Order} from "cowprotocol/libraries/GPv2Order.sol";

import {ConditionalOrder} from "../src/interfaces/ConditionalOrder.sol";
import {TWAPOrder} from "../src/libraries/TWAPOrder.sol";
import {CoWTWAPFallbackHandler} from "../src/CoWTWAPFallbackHandler.sol";

import "./Base.t.sol";

contract CoWTWAP is Base {

    event ConditionalOrderCreated(address indexed, bytes);

    CoWTWAPFallbackHandler twapSingleton;
    CoWTWAPFallbackHandler twapSafe;

    TWAPOrder.Data defaultBundle;
    bytes32 defaultBundleHash;
    bytes defaultBundleBytes;

    function setUp() public override(Base) virtual {
        super.setUp();

        // deploy the CoW TWAP fallback handler
        twapSingleton = new CoWTWAPFallbackHandler(settlement);

        // enable the CoW TWAP fallback handler for safe 1
        setFallbackHandler(safe1, twapSingleton);
        twapSafe = CoWTWAPFallbackHandler(address(safe1));

        // Set a default bundle
        defaultBundle = _twapTestBundle(block.timestamp + 1 days);
        defaultBundleBytes = abi.encode(defaultBundle);

        createOrder(
            GnosisSafe(payable(address(twapSafe))),
            defaultBundleBytes,
            defaultBundle.sellToken,
            defaultBundle.totalSellAmount
        );
    }

    /// @dev Test that the fallback handler can be set on a Safe and that it
    /// at least supports the safe interfaces as Compatability fallback handler.
    function testSetFallbackHandler() public {
        // set the fallback handler to the CoW TWAP fallback handler
        setFallbackHandler(safe2, twapSingleton);

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

    /// @dev Test creating a TWAP order (event emission)
    ///      A valid order has the following properties:
    ///      - The order is signed by the safe
    ///      - The order is not cancelled
    function testCreateTWAPOrder() public {
        /// @dev We use a new Safe for this test to illustrate that the fallback
        /// handler can be set on an arbitrary Safe.
        setFallbackHandler(safe2, twapSingleton);
        CoWTWAPFallbackHandler _twapSafe = CoWTWAPFallbackHandler(address(safe2));

        TWAPOrder.Data memory order = _twapTestBundle(block.timestamp);
        bytes memory orderBytes = abi.encode(order);

        // this should emit a ConditionalOrderCreated event
        vm.expectEmit(true, true, true, false);
        emit ConditionalOrderCreated(address(_twapSafe), orderBytes);

        // Everything here happens in a batch
        createOrder(
            GnosisSafe(payable(address(_twapSafe))),
            orderBytes,
            order.sellToken,
            order.totalSellAmount
        );

        // Check that the order signed by the safe.
        bytes32 orderDigest = ConditionalOrderLib.hash(orderBytes, settlement.domainSeparator());
        assertTrue(_twapSafe.isValidSignature(orderDigest, "") == bytes4(0x1626ba7e));

        // Check that the order is not cancelled
        bytes32 cancelDigest = ConditionalOrderLib.hashCancel(orderDigest, settlement.domainSeparator());
        vm.expectRevert(bytes("Hash not approved"));
        _twapSafe.isValidSignature(cancelDigest, "");
    }

    /// @dev Test cancelling a TWAP order
    ///      A cancelled order has the following properties:
    ///      - A cancel order message is signed by the safe
    function testCancelTWAPOrder() public {
        /// @dev Set block time to the start of the TWAP bundle
        vm.warp(defaultBundle.t0);

        // First check that the order is valid by getting a *part* of the TWAP bundle
        GPv2Order.Data memory part = twapSafe.getTradeableOrder(defaultBundleBytes);

        // Check that the order *part* is valid
        bytes32 partDigest = GPv2Order.hash(part, settlement.domainSeparator());
        assertTrue(twapSafe.isValidSignature(partDigest, defaultBundleBytes) == bytes4(0x1626ba7e));

        // Cancel the *TWAP order*
        bytes32 twapDigest = ConditionalOrderLib.hash(defaultBundleBytes, settlement.domainSeparator());
        bytes32 cancelDigest = ConditionalOrderLib.hashCancel(twapDigest, settlement.domainSeparator());
        safeSignMessage(safe1, abi.encode(cancelDigest));

        // Check that the *TWAP order* is cancelled
        twapSafe.isValidSignature(cancelDigest, "");

        // Try to get a *part* of the TWAP order
        vm.expectRevert(ConditionalOrder.OrderCancelled.selector);
        twapSafe.getTradeableOrder(defaultBundleBytes);

        // Check that the order is not valid
        vm.expectRevert(ConditionalOrder.OrderCancelled.selector);
        twapSafe.isValidSignature(partDigest, defaultBundleBytes);
    }

    /// @dev Test that the TWAP order is not valid before the start time
    function testNotValidBefore() public {
        vm.warp(defaultBundle.t0 - 1 seconds);
        vm.expectRevert(ConditionalOrder.OrderNotValid.selector);
        
        // attempt to get a part of the TWAP bundle
        twapSafe.getTradeableOrder(defaultBundleBytes);
    }

    /// @dev Test that the TWAP order is not valid after the end time
    ///      This test is a bit tricky because the TWAP order is valid for
    ///      `n` periods of length `t` starting at time `t0`. The order is
    ///      valid for the entire period, so the order is valid until
    ///      `t0 + n * t` exclusive.
    function testNotValidAfter() public {
        vm.warp(defaultBundle.t0 + (defaultBundle.n * defaultBundle.t));
        vm.expectRevert(ConditionalOrder.OrderExpired.selector);

        // get a part of the TWAP bundle
        twapSafe.getTradeableOrder(defaultBundleBytes);
    }

    function testNotValidAfterSpan() public {
        vm.warp(defaultBundle.t0 + defaultBundle.span);
        vm.expectRevert(ConditionalOrder.OrderNotValid.selector);

        // attempt to get a part of the TWAP bundle
        twapSafe.getTradeableOrder(defaultBundleBytes);
    }

    function _twapTestBundle(uint256 startTime) internal view returns (TWAPOrder.Data memory) {
        return
            TWAPOrder.Data({
                sellToken: token0,
                buyToken: token1,
                receiver: address(0), // the safe itself
                totalSellAmount: 1000e18,
                maxPartLimit: 100e18,
                t0: startTime,
                n: 10,
                t: 1 days,
                span: 12 hours
            });
    }
}