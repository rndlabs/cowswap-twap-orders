// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GPv2Settlement} from "cowprotocol/GPv2Settlement.sol";
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

    /// @dev Checks that the order is signed by the Safe and has not been cancelled.
    function _onlySignedAndNotCancelled(bytes memory order) internal view {
        (GnosisSafe safe, bytes32 domainSeparator, bytes32 digest) = safeLookup(order);

        /// @dev If the order has not been signed by the Safe, revert
        if (!isSignedConditionalOrder(safe, domainSeparator, digest)) {
            revert ConditionalOrder.OrderNotSigned();
        }

        /// @dev If the order has been cancelled by the Safe, revert
        if (isCancelledConditionalOrder(safe, domainSeparator, digest)) {
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
    /// @param _signature Any arbitrary data passed in to validate the order.
    /// @return A boolean indicating whether the signature is valid.
    function verifyOrder(bytes32, bytes memory _signature)
        internal
        view
        virtual
        returns (bool) 
    {
        (GnosisSafe safe, bytes32 domainSeparator, bytes32 digest) = safeLookup(_signature);
        if (!isSignedConditionalOrder(safe, domainSeparator, digest)) {
            return false;
        }

        if (isCancelledConditionalOrder(safe, domainSeparator, digest)) {
            revert ConditionalOrder.OrderCancelled();
        }

        return true;
    }

    /// @dev Returns false if the order has not been signed by the Safe
    /// @param safe The Gnosis Safe that is signing the order
    /// @param domainSeparator The domain separator of the Safe
    /// @param hash The hash of the order
    /// @return True if the order has been signed by the Safe
    function isSignedConditionalOrder(GnosisSafe safe, bytes32 domainSeparator, bytes32 hash) internal view returns (bool) {
        return safe.signedMessages(
            getMessageHashForSafe(domainSeparator, abi.encode(hash))
        ) != 0;
    }

    /// @dev Returns true if the order has been cancelled by the Safe
    /// @param safe The Gnosis Safe that is cancelling the order
    /// @param domainSeparator The domain separator of the Safe
    /// @param hash The hash of the order
    /// @return True if the order has been cancelled by the Safe
    function isCancelledConditionalOrder(GnosisSafe safe, bytes32 domainSeparator, bytes32 hash) internal view returns (bool) {
        return safe.signedMessages(
            getMessageHashForSafe(
                domainSeparator, 
                abi.encode(ConditionalOrderLib.hashCancel(hash, SETTLEMENT_DOMAIN_SEPARATOR))
            )
        ) != 0;
    }

    /// @dev Returns hash of a message that can be signed by owners.
    /// @param domainSeparator Domain separator of the Safe.
    /// @param message Message that should be hashed
    /// @return Message hash.
    function getMessageHashForSafe(bytes32 domainSeparator, bytes memory message) internal pure returns (bytes32) {
        bytes32 safeMessageHash = keccak256(abi.encode(SAFE_MSG_TYPEHASH, keccak256(message)));
        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, safeMessageHash));
    }

    /// @dev Returns the Gnosis Safe, domain separator and hash of the order
    /// @param order The order to be hashed
    /// @return The Gnosis Safe, domain separator and hash of the order
    function safeLookup(bytes memory order) internal view returns (GnosisSafe, bytes32, bytes32) {
        GnosisSafe safe = GnosisSafe(payable(msg.sender));
        bytes32 domainSeparator = safe.domainSeparator();
        bytes32 digest = ConditionalOrderLib.hash(order, SETTLEMENT_DOMAIN_SEPARATOR);
        return (safe, domainSeparator, digest);
    }
}