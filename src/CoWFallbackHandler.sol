// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GPv2Settlement} from "cowprotocol/GPv2Settlement.sol";
import {GPv2Order} from "cowprotocol/libraries/GPv2Order.sol";
import {GnosisSafe} from "safe/GnosisSafe.sol";

import {CompatibilityFallbackHandler} from "./vendored/CompatibilityFallbackHandler.sol";
import {ConditionalOrder} from "./interfaces/ConditionalOrder.sol";
import {ConditionalOrderLib} from "./libraries/ConditionalOrderLib.sol";

/// @title CoW Fallback Handler
/// @author mfw78 <mfw78@rndlabs.xyz>
/// @dev This is an abstract contract that smart orders can inherit from.
abstract contract CoWFallbackHandler is CompatibilityFallbackHandler, ConditionalOrder {
    /// @dev The domain separator from the settlement contract used to verify
    /// signatures.
    bytes32 internal immutable SETTLEMENT_DOMAIN_SEPARATOR;

    /// @dev The length of the conditional order in bytes to be overriden by the child contract.
    function CONDITIONAL_ORDER_BYTES_LENGTH() internal pure virtual returns (uint256);

    constructor(GPv2Settlement _settlementContract) {
        /// @dev Cache the domain separator from the settlement contract to save
        /// on gas costs. Any change to the settlement contract will require a
        /// new deployment of this contract.
        SETTLEMENT_DOMAIN_SEPARATOR = _settlementContract.domainSeparator();
    }

    
    function CONDITIONAL_ORDER_BYTES_LENGTH() internal pure virtual returns (uint256);

    function _onlySignedAndNotCancelled(bytes memory order) internal view {
        GnosisSafe safe = GnosisSafe(payable(msg.sender));
        bytes32 conditionalOrderDigest = ConditionalOrderLib.hash(
            order,
            SETTLEMENT_DOMAIN_SEPARATOR
        );

        /// @dev If the order has not been signed by the Safe, revert
        if (safe.signedMessages(getMessageHashForSafe(safe, abi.encode(conditionalOrderDigest))) == 0) {
            revert ConditionalOrder.OrderNotSigned();
        }

        /// @dev If the order has been cancelled by the Safe, revert
        if (
            safe.signedMessages(
                getMessageHashForSafe(
                    safe,
                    abi.encode(ConditionalOrderLib.hashCancel(conditionalOrderDigest, SETTLEMENT_DOMAIN_SEPARATOR))
                )
            ) != 0
        ) {
            revert ConditionalOrder.OrderCancelled();
        }
    }

    /// @inheritdoc ConditionalOrder
    function dispatch(bytes calldata payload) external override {
        _onlySignedAndNotCancelled(payload);
        emit ConditionalOrderCreated(msg.sender, payload);
    }

    /// @inheritdoc CompatibilityFallbackHandler
    /// @dev Should return whether the signature provided is valid for the provided data.
    /// 1. Try to verify the order using the smart order logic.
    /// 2. If the order verification fails, try to verify the signature using the
    ///    chained fallback handler.
    function isValidSignature(
        bytes32 _dataHash,
        bytes calldata _signature
    ) public view override returns (bytes4 magicValue) {
        /// @dev Only attempt to decode signatures of the expected length.
        ///      If not a pre-signed message, then try to verify the order.
        if (_signature.length == CONDITIONAL_ORDER_BYTES_LENGTH() && verifyOrder(_dataHash, _signature)) {
            return UPDATED_MAGIC_VALUE;
        }

        // If the order verification fails, try to verify the signature using the
        // chained fallback handler.
        return super.isValidSignature(_dataHash, _signature);
    }

    /// @dev An internal function that is overriden by the child contract when implementing
    /// the smart order logic.
    /// @param _hash The EIP-712 structHash of the GPv2Order.
    /// @param _signature Any arbitrary data passed in to validate the order.
    /// @return A boolean indicating whether the signature is valid.
    function verifyOrder(bytes32 _hash, bytes memory _signature)
        internal
        view
        virtual
        returns (bool);
}