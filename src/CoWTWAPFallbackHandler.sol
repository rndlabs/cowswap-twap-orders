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

    uint256 internal constant _CONDITIONAL_ORDER_BYTES_LENGTH = 288;

    constructor(GPv2Settlement _settlementContract)
        CoWFallbackHandler(_settlementContract)
    {}

    function getTradeableOrder(bytes calldata payload) 
        external
        view
        override
        returns (GPv2Order.Data memory) 
    {
        _onlySignedAndNotCancelled(payload);

        /// @dev Decode the payload into a TWAP bundle.
        TWAPOrder.Data memory bundle = abi.decode(payload, (TWAPOrder.Data));

        /// @dev Return the order from the bundle. `orderFor` will revert if there 
        /// is no order for the current block.
        return TWAPOrder.orderFor(bundle);
    }

    /// @inheritdoc CoWFallbackHandler
    /// @dev This function verifies that the order hash provided in the signature
    /// matches the hash of an order that is part of the TWAP bundle. The TWAP bundle is
    /// decoded from the signature and the order is extracted from the bundle.
    /// @param _signature An ABI-encoded TWAP bundle.
    function verifyOrder(bytes32 _hash, bytes memory _signature) 
        internal
        view
        override
        returns (bool)
    {
        /// @dev The signature must be the correct length to be a TWAP bundle.
        if (_signature.length != TWAPOrder.TWAP_ORDER_BYTES_LENGTH) {
            return false;
        }
    
        _onlySignedAndNotCancelled(_signature);

        /// @dev Decode the signature into a TWAP bundle.
        TWAPOrder.Data memory bundle = abi.decode(_signature, (TWAPOrder.Data));

        /// @dev Get the part of the TWAP bundle that is valid for the current block.
        ///      This will revert if there is no order for the current block.
        GPv2Order.Data memory order = TWAPOrder.orderFor(bundle);

        /// @dev The derived order hash must match the order hash provided in the signature. 
        return GPv2Order.hash(order, SETTLEMENT_DOMAIN_SEPARATOR) == _hash;
    }

    /// @inheritdoc CoWFallbackHandler
    function CONDITIONAL_ORDER_BYTES_LENGTH() 
        internal
        pure
        override
        returns (uint256)
    {
        return _CONDITIONAL_ORDER_BYTES_LENGTH;
    }
}