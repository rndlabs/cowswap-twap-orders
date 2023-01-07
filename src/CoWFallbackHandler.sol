// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {CompatibilityFallbackHandler} from "./vendored/safe/CompatibilityFallbackHandler.sol";
import {GPv2Settlement} from "./vendored/GPv2Settlement.sol";

import {ConditionalOrder} from "./interfaces/ConditionalOrder.sol";

/// @title CoW Fallback Handler
/// @author mfw78 <mfw78@rndlabs.xyz>
/// @dev This is an abstract contract that smart orders can inherit from.
abstract contract CoWFallbackHandler is CompatibilityFallbackHandler, ConditionalOrder {

    /// @dev The domain separator from the settlement contract used to verify
    /// signatures.
    bytes32 internal immutable SETTLEMENT_DOMAIN_SEPARATOR;

    constructor(GPv2Settlement _settlementContract) {
        /// @dev Cache the domain separator from the settlement contract to save
        /// on gas costs. Any change to the settlement contract will require a
        /// new deployment of this contract.
        SETTLEMENT_DOMAIN_SEPARATOR = _settlementContract.domainSeparator();
    }

    /// @dev Should return whether the signature provided is valid for the provided data. 
    /// 1. Try to verify the order using the smart order logic.
    /// 2. If the order verification fails, try to verify the signature using the
    ///    chained fallback handler. 
    /// @param _dataHash      Hash of the data to be signed
    /// @param _signature Signature byte array associated with _data
    /// MUST return the bytes4 magic value 0x1626ba7e when function passes.
    /// MUST NOT modify state (using STATICCALL for solc < 0.5, view modifier for
    /// solc > 0.5)
    /// MUST allow external calls
    ///
    function isValidSignature(bytes32 _dataHash, bytes calldata _signature)
        public
        view
        override
        returns (bytes4 magicValue)
    {
        // First try to verify the order using the smart order logic.
        if (verifyOrder(_dataHash, _signature)) {
            return UPDATED_MAGIC_VALUE;
        }

        // If the order verification fails, try to verify the signature using the
        // chained fallback handler.
        return super.isValidSignature(_dataHash, _signature);
    }

    /// @dev An internal function that is overriden by the child contract when implementing
    /// the smart order logic.
    /// @param _hash The hash of the data to be verified.
    /// @param _signature The signature of the data to be verified.
    /// @return A boolean indicating whether the signature is valid.
    function verifyOrder(bytes32 _hash, bytes memory _signature)
        internal
        view
        virtual
        returns (bool);
}