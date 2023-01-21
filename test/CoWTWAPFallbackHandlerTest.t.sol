// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";
import {IERC165} from "safe/interfaces/IERC165.sol";
import {ERC721TokenReceiver} from "safe/interfaces/ERC721TokenReceiver.sol";
import {ERC777TokensRecipient} from "safe/interfaces/ERC777TokensRecipient.sol";
import {ERC1155TokenReceiver} from "safe/interfaces/ERC1155TokenReceiver.sol";
import {CompatibilityFallbackHandler} from "safe/handler/CompatibilityFallbackHandler.sol";
import {GnosisSafe} from "safe/GnosisSafe.sol";

import {GPv2EIP1271} from "cowprotocol/interfaces/GPv2EIP1271.sol";
import {GPv2Order} from "cowprotocol/libraries/GPv2Order.sol";

import {ConditionalOrder} from "../src/interfaces/ConditionalOrder.sol";
import {TWAPOrder} from "../src/libraries/TWAPOrder.sol";
import {TWAPOrderMathLib} from "../src/libraries/TWAPOrderMathLib.sol";
import {CoWTWAPFallbackHandler} from "../src/CoWTWAPFallbackHandler.sol";

import "./Base.t.sol";

uint256 constant SELL_AMOUNT = 24000e18;
uint256 constant LIMIT_PRICE = 100e18;
uint32 constant FREQUENCY = 1 hours;
uint32 constant NUM_PARTS = 24;
uint32 constant SPAN = 5 minutes;

contract CoWTWAP is Base {

    event ConditionalOrderCreated(address indexed, bytes);

    CoWTWAPFallbackHandler twapSingleton;
    CoWTWAPFallbackHandler twapSafeWithOrder;
    CoWTWAPFallbackHandler twapSafe;

    TWAPOrder.Data defaultBundle;
    bytes32 defaultBundleHash;
    bytes defaultBundleBytes;

    mapping(bytes32 => uint256) public orderFills;

    function setUp() public virtual override(Base) {
        super.setUp();

        // deploy the CoW TWAP fallback handler
        twapSingleton = new CoWTWAPFallbackHandler(settlement);

        // enable the CoW TWAP fallback handler for safe 1
        setFallbackHandler(safe1, twapSingleton);
        twapSafeWithOrder = CoWTWAPFallbackHandler(address(safe1));

        // enable the CoW TWAP fallback handler for safe 3
        setFallbackHandler(safe3, twapSingleton);
        twapSafe = CoWTWAPFallbackHandler(address(safe3));

        // Set a default bundle
        defaultBundle = _twapTestBundle(block.timestamp + 1 days);
        defaultBundleBytes = abi.encode(defaultBundle);

        deal(address(token0), address(twapSafeWithOrder), SELL_AMOUNT);

        createOrder(
            GnosisSafe(payable(address(twapSafeWithOrder))),
            defaultBundleBytes,
            defaultBundle.sellToken,
            defaultBundle.partSellAmount * defaultBundle.n
        );
    }

    function test_SetUpState_CoWTWAPFallbackHandler_is_set() public {
        // check that the fallback handler is set
        // get the storage at 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5
        // which is the storage slot of the fallback handler
        assertEq(
            vm.load(address(safe1), 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5),
            bytes32(uint256(uint160(address(twapSingleton))))
        );
    }

    /// @dev An end to end test that sets the fallback handler on a Safe and then
    ///      checks that the fallback handler is set correctly checking expected functionality
    ///      from Compatability fallback handler.
    ///      Make use of safe2 to illustrate that the fallback handler can be set on an arbitrary Safe.
    function test_setFallbackHandler_e2e() public {
        // Check to make sure that the default fallback handler is set
        assertEq(
            vm.load(address(safe2), 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5),
            bytes32(uint256(uint160(address(handler))))
        );

        assertTrue(CompatibilityFallbackHandler(address(safe2)).supportsInterface(type(IERC165).interfaceId));
        assertTrue(CompatibilityFallbackHandler(address(safe2)).supportsInterface(type(ERC721TokenReceiver).interfaceId));
        assertTrue(CompatibilityFallbackHandler(address(safe2)).supportsInterface(type(ERC1155TokenReceiver).interfaceId));

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

    function test_inherited_CompatibilityFallbackHandler_supportsInterface() public {
        // check some of the standard interfaces that the fallback handler supports
        assertTrue(twapSafeWithOrder.supportsInterface(type(IERC165).interfaceId));
    }

    /// @dev Test inherited functionality from CompatibilityFallbackHandler
    function test_inherited_CompatibilityFallbackHandler_isValidSignature() public {
        // Get a message hash to sign
        bytes32 _msg = keccak256(bytes("Cows are cool"));
        bytes32 msgDigest = twapSafeWithOrder.getMessageHash(abi.encode(_msg));

        // Sign the message
        TestAccount[] memory signers = signers();
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = TestAccountLib.signPacked(signers[0], msgDigest);
        signatures[1] = TestAccountLib.signPacked(signers[1], msgDigest);

        // concatenate the signatures
        bytes memory sigs = abi.encodePacked(signatures[0], signatures[1]);

        // Check that the signature is valid
        assertTrue(twapSafeWithOrder.isValidSignature(_msg, sigs) == bytes4(GPv2EIP1271.MAGICVALUE));
    }

    function test_inherited_CompatibilityFallbackHandler_isValidSignature_RevertWhenNotValidSignature() public {
        // Get a message hash to sign
        bytes32 _msg = keccak256(bytes("Cows are cool"));
        bytes32 msgDigest = twapSafeWithOrder.getMessageHash(abi.encode(_msg));

        // Sign the message
        TestAccount[] memory signers = signers();
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = TestAccountLib.signPacked(signers[0], msgDigest);
        signatures[1] = TestAccountLib.signPacked(signers[1], msgDigest);

        // concatenate the signatures
        bytes memory sigs = abi.encodePacked(signatures[0], signatures[1]);

        // Check that the signature is valid
        assertTrue(twapSafeWithOrder.isValidSignature(_msg, sigs) == bytes4(GPv2EIP1271.MAGICVALUE));

        // Revert when not valid signature because Safe doesn't properly implement EIP1271
        // ie. it reverts instead of returning != bytes4(GPv2EIP1271.MAGICVALUE)
        bytes memory invalidSigs = abi.encodePacked(signatures[0], signatures[0]);
        vm.expectRevert();
        assertTrue(twapSafeWithOrder.isValidSignature(_msg, invalidSigs) != bytes4(GPv2EIP1271.MAGICVALUE));
    }

    function test_inherited_CompatibilityFallbackHandler_isValidSignature_RevertOnMalformedTWAP() public {
        // Generate a malformed TWAP, ie. random bytes of length 288
        bytes memory malformedTWAP = new bytes(288);
        for (uint256 i = 0; i < malformedTWAP.length; i++) {
            malformedTWAP[i] = bytes1(uint8(uint256(keccak256(abi.encodePacked(i))) % 256));
        }

        // Generate a malformed hash
        bytes32 malformedHash = keccak256(malformedTWAP);

        // Revert when not valid signature because Safe doesn't properly implement EIP1271
        // ie. it reverts instead of returning != bytes4(GPv2EIP1271.MAGICVALUE)
        vm.expectRevert();
        assertTrue(twapSafeWithOrder.isValidSignature(malformedHash, malformedTWAP) != bytes4(GPv2EIP1271.MAGICVALUE));
    }

    function test_dispatch_RevertOnSameTokens() public {
        // Revert when the same token is used for both the buy and sell token
        TWAPOrder.Data memory twapOrder = _twapTestBundle(block.timestamp);
        twapOrder.sellToken = token0;
        twapOrder.buyToken = token0;

        vm.expectRevert(TWAPOrder.InvalidSameToken.selector);
        twapSafe.dispatch(abi.encode(twapOrder));
    }

    function test_dispatch_RevertOnTokenZero() public {
        // Revert when either the buy or sell token is address(0)
        TWAPOrder.Data memory twapOrder = _twapTestBundle(block.timestamp);
        twapOrder.sellToken = IERC20(address(0));

        vm.expectRevert(TWAPOrder.InvalidToken.selector);
        twapSafe.dispatch(abi.encode(twapOrder));

        twapOrder.sellToken = token0;
        twapOrder.buyToken = IERC20(address(0));

        vm.expectRevert(TWAPOrder.InvalidToken.selector);
        twapSafe.dispatch(abi.encode(twapOrder));
    }

    function test_dispatch_RevertOnZeroPartSellAmount() public {
        // Revert when the sell amount is zero
        TWAPOrder.Data memory twapOrder = _twapTestBundle(block.timestamp);
        twapOrder.partSellAmount = 0;

        vm.expectRevert(TWAPOrder.InvalidPartSellAmount.selector);
        twapSafe.dispatch(abi.encode(twapOrder));
    }

    function test_dispatch_RevertOnZeroMinPartLimit() public {
        // Revert when the limit is zero
        TWAPOrder.Data memory twapOrder = _twapTestBundle(block.timestamp);
        twapOrder.minPartLimit = 0;

        vm.expectRevert(TWAPOrder.InvalidMinPartLimit.selector);
        twapSafe.dispatch(abi.encode(twapOrder));
    }

    function test_dispatch_FuzzRevertOnInvalidStartTime(uint256 startTime) public {
        vm.assume(startTime >= type(uint32).max);
        // Revert when the start time exceeds or equals the max uint32
        TWAPOrder.Data memory twapOrder = _twapTestBundle(startTime);
        twapOrder.t0 = startTime;

        vm.expectRevert(TWAPOrder.InvalidStartTime.selector);
        twapSafe.dispatch(abi.encode(twapOrder));
    }

    function test_dispatch_FuzzRevertOnInvalidNumParts(uint256 numParts) public {
        vm.assume(numParts < 2 || numParts >= type(uint32).max);
        // Revert if not an actual TWAP (ie. numParts < 2)
        TWAPOrder.Data memory twapOrder = _twapTestBundle(block.timestamp);
        twapOrder.n = numParts;

        vm.expectRevert(TWAPOrder.InvalidNumParts.selector);
        twapSafe.dispatch(abi.encode(twapOrder));
    }

    function test_dispatch_FuzzRevertOnInvalidFrequency(uint256 frequency) public {
        vm.assume(frequency < 1 || frequency >= type(uint32).max);
        TWAPOrder.Data memory twapOrder = _twapTestBundle(block.timestamp);
        twapOrder.t = frequency;

        vm.expectRevert(TWAPOrder.InvalidFrequency.selector);
        twapSafe.dispatch(abi.encode(twapOrder));
    }

    function test_dispatch_FuzzRevertOnInvalidSpan(uint256 frequency, uint256 span) public {
        vm.assume(frequency > 0 && frequency < type(uint32).max);
        vm.assume(span > frequency);

        TWAPOrder.Data memory twapOrder = _twapTestBundle(block.timestamp);
        twapOrder.t = frequency;
        twapOrder.span = span;

        vm.expectRevert(TWAPOrder.InvalidSpan.selector);
        twapSafe.dispatch(abi.encode(twapOrder));
    }

    function test_dispatch_RevertOnOrderNotSigned() public {
        // Revert when the order is not signed by the safe
        TWAPOrder.Data memory twapOrder = _twapTestBundle(block.timestamp);
        bytes memory orderBytes = abi.encode(twapOrder);

        vm.expectRevert(ConditionalOrder.OrderNotSigned.selector);
        twapSafe.dispatch(orderBytes);
    }

    function test_dispatch_RevertOnOrderSignedAndCancelled() public {
        // Revert when the order is signed by the safe and cancelled
        TWAPOrder.Data memory order = _twapTestBundle(block.timestamp);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Verify that the order is valid - this shouldn't revert
        twapSafe.getTradeableOrder(orderBytes);

        // Cancel the *TWAP order*
        bytes32 twapDigest = ConditionalOrderLib.hash(orderBytes, settlement.domainSeparator());
        bytes32 cancelDigest = ConditionalOrderLib.hashCancel(twapDigest, settlement.domainSeparator());
        safeSignMessage(GnosisSafe(payable(address(twapSafe))), abi.encode(cancelDigest));

        vm.expectRevert(ConditionalOrder.OrderCancelled.selector);
        twapSafe.dispatch(orderBytes);
    }

    /// @dev Test creating a TWAP order (event emission)
    ///      A valid order has the following properties:
    ///      - The order is signed by the safe
    ///      - The order is not cancelled
    function test_dispatch_e2e() public {
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
        createOrder(GnosisSafe(payable(address(_twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Check that the order signed by the safe.
        bytes32 orderDigest = ConditionalOrderLib.hash(orderBytes, settlement.domainSeparator());
        assertTrue(_twapSafe.isValidSignature(orderDigest, "") == bytes4(GPv2EIP1271.MAGICVALUE));

        // Check that the order is not cancelled
        bytes32 cancelDigest = ConditionalOrderLib.hashCancel(orderDigest, settlement.domainSeparator());
        vm.expectRevert(bytes("Hash not approved"));
        _twapSafe.isValidSignature(cancelDigest, "");
    }

    function test_getTradeableOrder_RevertOnOrderNotSigned() public {
        // Revert when the order is not signed by the safe
        TWAPOrder.Data memory twapOrder = _twapTestBundle(block.timestamp);
        bytes memory orderBytes = abi.encode(twapOrder);

        vm.expectRevert(ConditionalOrder.OrderNotSigned.selector);
        twapSafe.getTradeableOrder(orderBytes);
    }

    function test_getTradeableOrder_RevertOnOrderSignedAndCancelled() public {
        // Revert when the order is signed by the safe and cancelled
        TWAPOrder.Data memory order = _twapTestBundle(block.timestamp);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Verify that the order is valid - this shouldn't revert
        twapSafe.getTradeableOrder(orderBytes);

        // Cancel the *TWAP order*
        bytes32 twapDigest = ConditionalOrderLib.hash(orderBytes, settlement.domainSeparator());
        bytes32 cancelDigest = ConditionalOrderLib.hashCancel(twapDigest, settlement.domainSeparator());
        safeSignMessage(GnosisSafe(payable(address(twapSafe))), abi.encode(cancelDigest));

        vm.expectRevert(ConditionalOrder.OrderCancelled.selector);
        twapSafe.getTradeableOrder(orderBytes);
    }

    function test_getTradeableOrder_FuzzRevertIfBeforeStart(uint256 startTime, uint256 currentTime) public {
        // guard against overflows
        vm.assume(startTime < type(uint32).max);
        // force revert before start
        vm.assume(currentTime < startTime);

        // Revert when the order is signed by the safe and cancelled
        TWAPOrder.Data memory order = _twapTestBundle(startTime);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Warp to start time to make sure the order is valid
        vm.warp(startTime);

        // Verify that the order is valid - this shouldn't revert
        twapSafe.getTradeableOrder(orderBytes);

        // Warp to current time
        vm.warp(currentTime);

        vm.expectRevert(ConditionalOrder.OrderNotValid.selector);
        twapSafe.getTradeableOrder(orderBytes);
    }

    function test_getTradeableOrder_FuzzRevertIfExpired(uint256 startTime, uint256 currentTime) public {
        // guard against overflows
        vm.assume(startTime < type(uint32).max);
        // force revert after expiry
        vm.assume(currentTime >= startTime + (FREQUENCY * NUM_PARTS));

        // Revert when the order is signed by the safe and cancelled
        TWAPOrder.Data memory order = _twapTestBundle(startTime);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Warp to start time to make sure the order is valid
        vm.warp(startTime);

        // Verify that the order is valid - this shouldn't revert
        twapSafe.getTradeableOrder(orderBytes);

        // Warp to expiry
        vm.warp(currentTime);

        vm.expectRevert(ConditionalOrder.OrderExpired.selector);
        twapSafe.getTradeableOrder(orderBytes);
    }

    function test_getTradeableOrder_FuzzRevertIfOutsideSpan(uint256 startTime, uint256 currentTime) public {
        // guard against overflows
        vm.assume(startTime < type(uint32).max);
        vm.assume(currentTime < type(uint32).max);
        // guard against revert before start
        vm.assume(startTime < currentTime);
        // guard against revert after expiry
        vm.assume(currentTime < startTime + (FREQUENCY * NUM_PARTS));
        // guard against no reversion when within span
        vm.assume((currentTime - startTime) % FREQUENCY >= SPAN);
        // Revert when the order is signed by the safe and cancelled
        TWAPOrder.Data memory order = _twapTestBundle(startTime);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        vm.warp(startTime);

        // Verify that the order is valid - this shouldn't revert
        twapSafe.getTradeableOrder(orderBytes);

        // Warp to within the span
        vm.warp(currentTime);

        vm.expectRevert(ConditionalOrder.OrderNotValid.selector);
        twapSafe.getTradeableOrder(orderBytes);
    }

    function test_getTradeableOrder_e2e_fuzz(uint256 startTime, uint256 currentTime) public {
        // guard against overflows
        vm.assume(startTime < type(uint32).max);
        vm.assume(currentTime < type(uint32).max);
        // guard against revert before start
        vm.assume(startTime < currentTime);
        // guard against revert after expiry
        vm.assume(currentTime < startTime + (FREQUENCY * NUM_PARTS));
        // guard against reversion outside of the span
        vm.assume((currentTime - startTime) % FREQUENCY < SPAN);
        // Revert when the order is signed by the safe and cancelled
        TWAPOrder.Data memory order = _twapTestBundle(startTime);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Warp to the current time
        vm.warp(currentTime);

        // This should not revert
        GPv2Order.Data memory part = twapSafe.getTradeableOrder(orderBytes);

        // Verify that the order is valid - this shouldn't revert
        assertTrue(twapSafe.isValidSignature(GPv2Order.hash(part, settlement.domainSeparator()), orderBytes) == GPv2EIP1271.MAGICVALUE);
    }

    function test_isValidSignature_RevertIfOrderNotSigned() public {
        // Revert when the order is signed by the safe and cancelled
        TWAPOrder.Data memory order = _twapTestBundle(block.timestamp + 1);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Warp to within the span
        vm.warp(order.t0);

        // This should not revert
        GPv2Order.Data memory part = twapSafe.getTradeableOrder(orderBytes);

        // Verify that the order is valid - this shouldn't revert
        assertTrue(twapSafe.isValidSignature(GPv2Order.hash(part, settlement.domainSeparator()), orderBytes) == GPv2EIP1271.MAGICVALUE);

        // Try to verify the signature with a different order
        TWAPOrder.Data memory order2 = _twapTestBundle(block.timestamp + 10);
        bytes memory orderBytes2 = abi.encode(order2);

        vm.warp(order2.t0);

        // This should revert
        bytes32 hash = GPv2Order.hash(part, settlement.domainSeparator());
        vm.expectRevert(bytes("GS022"));
        twapSafe.isValidSignature(hash, orderBytes2);
    }

    function test_isValidSignature_RevertIfSignedAndCancelled() public {
        // Revert when the order is signed by the safe and cancelled
        TWAPOrder.Data memory order = _twapTestBundle(block.timestamp + 1);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Warp to within the span
        vm.warp(order.t0);

        // This should not revert
        GPv2Order.Data memory part = twapSafe.getTradeableOrder(orderBytes);

        // Verify that the order is valid - this shouldn't revert
        assertTrue(twapSafe.isValidSignature(GPv2Order.hash(part, settlement.domainSeparator()), orderBytes) == GPv2EIP1271.MAGICVALUE);

        // Cancel the order
        bytes32 twapDigest = ConditionalOrderLib.hash(orderBytes, settlement.domainSeparator());
        bytes32 cancelDigest = ConditionalOrderLib.hashCancel(twapDigest, settlement.domainSeparator());
        safeSignMessage(GnosisSafe(payable(address(twapSafe))), abi.encode(cancelDigest));

        // This should revert
        bytes32 hash = GPv2Order.hash(part, settlement.domainSeparator());
        vm.expectRevert(ConditionalOrder.OrderCancelled.selector);
        twapSafe.isValidSignature(hash, orderBytes);
    }

    function test_isValidSignature_FuzzRevertIfBeforeStart(uint256 startTime, uint256 currentTime) public {
        // guard against overflows
        vm.assume(startTime < type(uint32).max);
        // force revert before start
        vm.assume(currentTime < startTime);

        TWAPOrder.Data memory order = _twapTestBundle(startTime);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Warp to before the start
        vm.warp(currentTime);

        // This should revert
        vm.expectRevert(ConditionalOrder.OrderNotValid.selector);
        twapSafe.isValidSignature(keccak256("cow to alpha centauri"), orderBytes);
    }

    function test_isValidSignature_FuzzRevertIfExpired(uint256 startTime, uint256 currentTime) public {
        // guard against overflows
        vm.assume(startTime < type(uint32).max);
        // force revert after expiry
        vm.assume(currentTime >= startTime + (FREQUENCY * NUM_PARTS));

        TWAPOrder.Data memory order = _twapTestBundle(startTime);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Warp to after the expiry
        vm.warp(currentTime);

        // This should revert
        vm.expectRevert(ConditionalOrder.OrderExpired.selector);
        twapSafe.isValidSignature(keccak256("cow over the moon"), orderBytes);
    }

    function test_isValidSignature_FuzzRevertIfOutsideSpan(uint256 startTime, uint256 currentTime) public {
        // guard against overflows
        vm.assume(startTime < type(uint32).max);
        vm.assume(currentTime < type(uint32).max);
        // guard against revert before start
        vm.assume(startTime < currentTime);
        // guard against revert after expiry
        vm.assume(currentTime < startTime + (FREQUENCY * NUM_PARTS));
        // force revert outside of the span
        vm.assume((currentTime - startTime) % FREQUENCY >= SPAN);

        TWAPOrder.Data memory order = _twapTestBundle(startTime);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Warp to where the order is not valid
        vm.warp(currentTime);

        // This should revert
        vm.expectRevert(ConditionalOrder.OrderNotValid.selector);
        twapSafe.isValidSignature(keccak256("cow to alpha centauri"), orderBytes);
    }

    function test_isValidSignature_e2e_fuzz(uint256 startTime, uint256 currentTime) public {
        // guard against overflows
        vm.assume(startTime < type(uint32).max);
        vm.assume(currentTime < type(uint32).max);
        // guard against revert before start
        vm.assume(startTime < currentTime);
        // guard against revert after expiry
        vm.assume(currentTime < startTime + (FREQUENCY * NUM_PARTS));
        // guard against reversion outside of the span
        vm.assume((currentTime - startTime) % FREQUENCY < SPAN);
        // Revert when the order is signed by the safe and cancelled
        TWAPOrder.Data memory order = _twapTestBundle(startTime);
        bytes memory orderBytes = abi.encode(order);

        // Create the order - this signs the order and marks it a valid
        createOrder(GnosisSafe(payable(address(twapSafe))), orderBytes, order.sellToken, order.partSellAmount * order.n);

        // Warp to the current time
        vm.warp(currentTime);

        // This should not revert
        GPv2Order.Data memory part = twapSafe.getTradeableOrder(orderBytes);

        // Verify that the order is valid - this shouldn't revert
        assertTrue(twapSafe.isValidSignature(GPv2Order.hash(part, settlement.domainSeparator()), orderBytes) == GPv2EIP1271.MAGICVALUE);
    }

    /// @dev Simulate the TWAP order by iterating over every second and checking
    ///      that the number of parts is correct.
    function testSimulateTWAP() public {
        uint256 totalFills;
        uint256 numSecondsProcessed;

        vm.warp(defaultBundle.t0);

        while (true) {
            try twapSafeWithOrder.getTradeableOrder(defaultBundleBytes) returns (GPv2Order.Data memory order) {
                bytes32 orderDigest = GPv2Order.hash(order, settlement.domainSeparator());
                if (
                    orderFills[orderDigest] == 0
                        && twapSafeWithOrder.isValidSignature(orderDigest, defaultBundleBytes) == GPv2EIP1271.MAGICVALUE
                ) {
                    orderFills[orderDigest] = 1;
                    totalFills++;
                }

                // only count this second if we didn't revert
                numSecondsProcessed++;
            } catch (bytes memory lowLevelData) {
                bytes4 desiredSelector = bytes4(keccak256(bytes("OrderExpired()")));
                bytes4 receivedSelector = bytes4(lowLevelData);
                if (receivedSelector == desiredSelector) {
                    break;
                }
            }
            vm.warp(block.timestamp + 1 seconds);
        }

        // the timestamp should be equal to the end time of the TWAP order
        assertTrue(block.timestamp == defaultBundle.t0 + defaultBundle.n * defaultBundle.t);
        // the number of seconds processed should be equal to the number of
        // parts times span (if span is not 0)
        assertTrue(numSecondsProcessed == defaultBundle.n * defaultBundle.span);
        // the number of fills should be equal to the number of parts
        assertTrue(totalFills == defaultBundle.n);
    }

    /// @dev Simulate the TWAP order with a span of 0
    function testSimulateTWAPNoSpan() public {
        TWAPOrder.Data memory noSpanBundle = _twapTestBundle(block.timestamp + 10 days);
        noSpanBundle.n = NUM_PARTS / 2;
        noSpanBundle.t = FREQUENCY / 2;
        noSpanBundle.span = 0;
        bytes memory noSpanBundleBytes = abi.encode(noSpanBundle);

        // create the TWAP order
        createOrder(
            GnosisSafe(payable(address(twapSafeWithOrder))),
            noSpanBundleBytes,
            noSpanBundle.sellToken,
            noSpanBundle.partSellAmount * noSpanBundle.n
        );

        uint256 totalFills;
        uint256 numSecondsProcessed;

        vm.warp(noSpanBundle.t0);

        while (true) {
            try twapSafeWithOrder.getTradeableOrder(noSpanBundleBytes) returns (GPv2Order.Data memory order) {
                bytes32 orderDigest = GPv2Order.hash(order, settlement.domainSeparator());
                if (
                    orderFills[orderDigest] == 0
                        && twapSafeWithOrder.isValidSignature(orderDigest, noSpanBundleBytes) == GPv2EIP1271.MAGICVALUE
                ) {
                    orderFills[orderDigest] = 1;
                    totalFills++;
                }
                // only count this second if we didn't revert
                numSecondsProcessed++;
            } catch (bytes memory lowLevelData) {
                bytes4 failedSelected = bytes4(keccak256(bytes("OrderNotValid()")));
                bytes4 desiredSelector = bytes4(keccak256(bytes("OrderExpired()")));
                bytes4 receivedSelector = bytes4(lowLevelData);

                // The order should always be valid because there is no span
                if (receivedSelector == failedSelected) {
                    revert("OrderNotValid() should not be thrown");
                }

                // The order should expire after the last period
                if (receivedSelector == desiredSelector) {
                    break;
                }
                revert();
            }
            vm.warp(block.timestamp + 1 seconds);
        }
        // the timestamp should be equal to the end time of the TWAP order
        assertTrue(block.timestamp == noSpanBundle.t0 + noSpanBundle.n * noSpanBundle.t);
        // the number of seconds processed should be equal to the number of
        // parts times span (if span is not 0)
        assertTrue(numSecondsProcessed == noSpanBundle.n * noSpanBundle.t);
        // the number of fills should be equal to the number of parts
        assertTrue(totalFills == noSpanBundle.n);
    }

    /// @dev Fuzz test `calculateValidTo` function
    /// @param currentTime The current time
    /// @param startTime The start time of the TWAP order
    /// @param numParts The number of parts in the TWAP order
    /// @param frequency The frequency of the TWAP order
    /// @param span The span of the TWAP order
    function test_calculateValidTo(
        uint256 currentTime,
        uint256 startTime,
        uint256 numParts,
        uint256 frequency,
        uint256 span
    ) public {
        // --- Implicit assumptions
        // currentTime is always set to the current block timestamp in the TWAP order, so we can assume that it is less
        // than the max uint32 value.
        vm.assume(currentTime <= type(uint32).max);

        // --- Assertions
        // number of parts is asserted to be less than the max uint32 value in the TWAP order, so we can assume that it is
        // less than the max uint32 value.
        numParts = bound(numParts, 2, type(uint32).max);

        // frequency is asserted to be less than 365 days worth of seconds in the TWAP order, and at least 1 second
        vm.assume(frequency >= 1 && frequency <= 365 days);

        // The span is defined as the number of seconds that the TWAP order is valid for within each period. If the span
        // is 0, then the TWAP order is valid for the entire period. We can assume that the span is less than or equal
        // to the frequency.
        vm.assume(span <= frequency);

        // --- In-function revert conditions
        // We only calculate `validTo` if we are within the TWAP order's time window, so we can assume that the current
        // time is greater than or equal to the start time.
        vm.assume(currentTime >= startTime);

        // The TWAP order is deemed expired if the current time is greater than the end time of the last part. We can
        // assume that the current time is less than the end time of the TWAP order.
        vm.assume(currentTime < startTime + (numParts * frequency));

        uint256 part = (currentTime - startTime) / frequency;

        // The TWAP order is only valid for the span within each period, so we can assume that the current time is less
        // than the end time of the current part.
        vm.assume(currentTime < startTime + ((part + 1) * frequency) - (span != 0 ? (frequency - span) : 0));

        // --- Warp to the current time
        vm.warp(currentTime);

        uint256 validTo = TWAPOrderMathLib.calculateValidTo(startTime, numParts, frequency, span);

        uint256 expectedValidTo = startTime + ((part + 1) * frequency) - (span != 0 ? (frequency - span) : 0) - 1;

        // `validTo` MUST be now or in the future.
        assertTrue(validTo >= currentTime);
        // `validTo` MUST be equal to this.
        assertTrue(validTo == expectedValidTo);
    }

    function _twapTestBundle(uint256 startTime) internal view returns (TWAPOrder.Data memory) {
        return TWAPOrder.Data({
            sellToken: token0,
            buyToken: token1,
            receiver: address(0), // the safe itself
            partSellAmount: SELL_AMOUNT / NUM_PARTS,
            minPartLimit: LIMIT_PRICE,
            t0: startTime,
            n: NUM_PARTS,
            t: FREQUENCY,
            span: SPAN
        });
    }
}
