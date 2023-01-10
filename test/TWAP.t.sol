// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GnosisSafe} from "../lib/safe/contracts/GnosisSafe.sol";
import {Enum} from "../lib/safe/contracts/common/Enum.sol";

import "./Base.t.sol";
import {CoWTWAPFallbackHandler} from "../src/CoWTWAPFallbackHandler.sol";
import "./libraries/TestAccountLib.sol";

import {ConditionalOrder} from "../src/interfaces/ConditionalOrder.sol";
import {IERC20} from "../src/vendored/interfaces/IERC20.sol";
import {GPv2Order} from "../src/vendored/libraries/GPv2Order.sol";
import {TWAPOrder} from "../src/libraries/TWAPOrder.sol";

import {IERC165} from "../lib/safe/contracts/interfaces/IERC165.sol";
import {ERC721TokenReceiver} from "../lib/safe/contracts/interfaces/ERC721TokenReceiver.sol";
import {ERC777TokensRecipient} from "../lib/safe/contracts/interfaces/ERC777TokensRecipient.sol";
import {ERC1155TokenReceiver} from "../lib/safe/contracts/interfaces/ERC1155TokenReceiver.sol";

contract CoWTWAP is Base {
    using TestAccountLib for TestAccount[];
    using TWAPOrder for TWAPOrder.Data;
    using GPv2Order for GPv2Order.Data;

    event ConditionalOrderCreated(address indexed, bytes);
    GnosisSafe public safe;
    CoWTWAPFallbackHandler twapHandler;
    CoWTWAPFallbackHandler twap;

    function setUp() public override(Base) virtual {
        super.setUp();

        // create a safe with alice, bob and carol as owners
        address[] memory owners = new address[](3);
        owners[0] = alice.addr;
        owners[1] = bob.addr;
        owners[2] = carol.addr;

        // create the safe with a threshold of 2
        safe = GnosisSafe(payable(createSafe(owners, 2)));

        // deploy the CoW TWAP fallback handler
        twapHandler = new CoWTWAPFallbackHandler(settlement);

        // sign the transaction by alice and bob (sort their account by ascending order)
        // TestAccount[] memory _signers = new TestAccount[](2);
        // _signers[0] = alice;
        // _signers[1] = bob;
    }

    function testCreateTWAP() public {
        // set the fallback handler to the CoW TWAP fallback handler
        _enableTWAP();

        TestAccount[] memory signers = new TestAccount[](2);
        signers[0] = alice;
        signers[1] = bob;

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

        // 1. create a TWAP order
        bytes32 typedHash = bundle.hash(settlement.domainSeparator());

        // this should emit a ConditionalOrderCreated event
        vm.expectEmit(true, true, true, false);
        emit ConditionalOrderCreated(address(safe), abi.encode(bundle));

        // Everything here happens in a batch
        execute(
            safe,
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
                        address(safe),
                        uint256(0),
                        uint256(388), // 4 bytes for the selector + 384 bytes for the bundle variable length header
                        abi.encodeWithSelector(
                            twap.dispatch.selector,
                            abi.encode(bundle)
                        )
                    )
                )
            ),
            Enum.Operation.DelegateCall,
            signers
        );

        // get a part of the TWAP bundle
        GPv2Order.Data memory order = twap.getTradeableOrder(abi.encode(bundle));
        console.logBytes(abi.encode(order));

        // Test the isValidSignature function
        bytes32 orderDigest = order.hash(settlement.domainSeparator());

        assertTrue(twap.isValidSignature(orderDigest, abi.encode(bundle)) == bytes4(0x1626ba7e));

        // fast forward to the end of the span
        vm.warp(block.timestamp + 12 hours + 1 minutes);

        assertTrue(twap.isValidSignature(orderDigest, abi.encode(bundle)) != bytes4(0x1626ba7e));
    }

    function testSetCoWTWAPFallbackHandler() public {
        // set the fallback handler to the CoW TWAP fallback handler
        _enableTWAP();

        // check that the fallback handler is set
        // get the storage at 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5
        // which is the storage slot of the fallback handler
        assertEq(
            vm.load(address(safe), 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5),
            bytes32(uint256(uint160(address(twapHandler))))
        );

        // check some of the standard interfaces that the fallback handler supports
        CoWTWAPFallbackHandler _safe = CoWTWAPFallbackHandler(address(safe));
        assertTrue(_safe.supportsInterface(type(IERC165).interfaceId));
        assertTrue(_safe.supportsInterface(type(ERC721TokenReceiver).interfaceId));
        assertTrue(_safe.supportsInterface(type(ERC1155TokenReceiver).interfaceId));
    }

    function _enableTWAP() internal {
        twap = CoWTWAPFallbackHandler(address(safe));

        // declare the signers
        TestAccount[] memory signers = new TestAccount[](2);
        signers[0] = alice;
        signers[1] = bob;

        // do the transaction
        execute(
            safe,
            address(safe),
            0,
            abi.encodeWithSelector(
                safe.setFallbackHandler.selector,
                address(twapHandler)
            ),
            Enum.Operation.Call,
            signers
        );
    }
}