// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GPv2Order} from "cowprotocol/libraries/GPv2Order.sol";
import {GPv2Settlement} from "cowprotocol/GPv2Settlement.sol";

import {GnosisSafe} from "safe/GnosisSafe.sol";

import {TWAPOrder} from "./libraries/TWAPOrder.sol";
import {CoWFallbackHandler} from "./CoWFallbackHandler.sol";

/// @title CoW TWAP Fallback Handler
/// @author mfw78 <mfw78@rndlabs.xyz>
/// @dev A fallback handler to enable TWAP orders on Safe, settling via CoW.
contract CoWTWAPFallbackHandler is CoWFallbackHandler {
    using TWAPOrder for TWAPOrder.Data;
    using GPv2Order for GPv2Order.Data;

    constructor(GPv2Settlement _settlementContract)
        CoWFallbackHandler(_settlementContract)
    {}

    function getTradeableOrder(bytes calldata payload) 
        external
        view
        override
        onlySignedAndNotCancelled(payload) 
        returns (GPv2Order.Data memory) 
    {
        TWAPOrder.Data memory bundle = abi.decode(payload, (TWAPOrder.Data));
        // 1. Verify the TWAP bundle is signed by the Safe and not cancelled.
        bundle.onlySignedAndNotCancelled(
            GnosisSafe(payable(msg.sender)),
            SETTLEMENT_DOMAIN_SEPARATOR
        );

        // 2. The TWAP bundle is valid, so return the order that is part of the bundle.
        return bundle.orderFor();
    }

    function verifyOrder(bytes32 _hash, bytes memory _signature) 
        internal
        view
        override
        onlySignedAndNotCancelled(_signature)
        returns (bool)
    {
        TWAPOrder.Data memory bundle = abi.decode(_signature, (TWAPOrder.Data));

        // 2. The order submitted must be a part of the TWAP bundle. Get the order
        // from the bundle and verify the hash. `orderFor` will revert if the
        // order is not part of the bundle.
        GPv2Order.Data memory order = bundle.orderFor();

        // 3. Check the part of the order is the same as the hash. If so, the signature
        // is valid.
        return order.hash(SETTLEMENT_DOMAIN_SEPARATOR) == _hash;
    }

}