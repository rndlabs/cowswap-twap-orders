// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GPv2Order} from "cowprotocol/libraries/GPv2Order.sol";
import {GPv2Settlement} from "cowprotocol/GPv2Settlement.sol";

import {TWAPOrder} from "./libraries/TWAPOrder.sol";
import {CoWFallbackHandler} from "./CoWFallbackHandler.sol";

/// @title CoW TWAP Fallback Handler
/// @author mfw78 <mfw78@rndlabs.xyz>
/// @dev A fallback handler to enable TWAP orders on Safe, settling via CoW Protocol.
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
        /// @dev Decode the payload into a TWAP bundle.
        TWAPOrder.Data memory bundle = abi.decode(payload, (TWAPOrder.Data));

        /// @dev Return the order from the bundle. `orderFor` will revert if there 
        /// is no order for the current block.
        return bundle.orderFor();
    }

    /// @inheritdoc CoWFallbackHandler
    /// @param _signature An ABI-encoded TWAP bundle.
    function verifyOrder(bytes32 _hash, bytes memory _signature) 
        internal
        view
        override
        onlySignedAndNotCancelled(_signature)
        returns (bool)
    {
        /// @dev The signature must be the correct length to be a TWAP bundle.
        if (_signature.length != TWAPOrder.TWAP_ORDER_BYTES_LENGTH) {
            return false;
        }

        /// @dev Decode the signature into a TWAP bundle.
        TWAPOrder.Data memory bundle = abi.decode(_signature, (TWAPOrder.Data));

        /// @dev The order submitted must be a part of the TWAP bundle. Get the order
        /// from the bundle and verify the hash. `orderFor` will revert if the
        /// order is not part of the bundle.
        GPv2Order.Data memory order = bundle.orderFor();

        /// @dev The derived order hash must match the order hash provided in the
        /// signature. 
        return order.hash(SETTLEMENT_DOMAIN_SEPARATOR) == _hash;
    }
}