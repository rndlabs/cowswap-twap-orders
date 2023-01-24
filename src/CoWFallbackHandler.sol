// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GnosisSafe} from "safe/GnosisSafe.sol";

import {CompatibilityFallbackHandler} from "./vendored/CompatibilityFallbackHandler.sol";
import {CoWSettlement} from "./vendored/CoWSettlement.sol";
import {ConditionalOrder} from "./interfaces/ConditionalOrder.sol";
import {ConditionalOrderLib} from "./libraries/ConditionalOrderLib.sol";

/// @title CoW `ConditionalOrder` Fallback Handler
/// @author mfw78 <mfw78@rndlabs.xyz>
/// @dev This is an abstract contract that `ConditionalOrder`s inherit from.
abstract contract CoWFallbackHandler is CompatibilityFallbackHandler, ConditionalOrder {
    /// @dev The domain separator from the settlement contract used to verify
    /// signatures.
    bytes32 internal immutable SETTLEMENT_DOMAIN_SEPARATOR;

    /// @dev The length of the conditional order in bytes to be overriden by the child contract.
    function CONDITIONAL_ORDER_BYTES_LENGTH() internal pure virtual returns (uint256);

    constructor(address _settlementContract) {
        /// @dev Cache the domain separator from the settlement contract to save
        /// on gas costs. Any change to the settlement contract will require a
        /// new deployment of this contract.
        SETTLEMENT_DOMAIN_SEPARATOR = CoWSettlement(_settlementContract).domainSeparator();
    }

    /// @dev Checks that the order is signed by the Safe and has not been cancelled.
    /// Reverts if the order is not signed or has been cancelled.
    /// @param order The conditional order to check.
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
    function dispatch(bytes calldata payload) public virtual override {
        _onlySignedAndNotCancelled(payload);
        emit ConditionalOrderCreated(msg.sender, payload);
    }

    /// @inheritdoc CompatibilityFallbackHandler
    /// @dev Should return whether the signature provided is valid for the provided _dataHash.
    /// 1. Try to verify the conditional order using the order's logic.
    /// 2. If the order verification fails, try to verify the signature using the
    ///    standard `CompatibilityFallbackHandler`.
    function isValidSignature(bytes32 _dataHash, bytes calldata _signature)
        public
        view
        override
        returns (bytes4 magicValue)
    {
        /// @dev Only attempt to decode signatures of the expected length. This has the added
        /// benefit of calling `super` early if the signature is a pre-signed message (ie. `_signature`
        /// of `bytes` length 0).
        if (_signature.length == CONDITIONAL_ORDER_BYTES_LENGTH() && verifyTrade(_dataHash, _signature)) {
            return UPDATED_MAGIC_VALUE;
        }

        // If the order verification fails, try to verify the signature using the
        // standard `CompatibilityFallbackHandler`.
        return super.isValidSignature(_dataHash, _signature);
    }

    /// @dev An internal function that is overriden by the child contract when implementing
    /// the conditional order logic. Inheriting contracts should call this function to the 
    /// signed order and check that it has not been cancelled.
    /// @param payload Any arbitrary data passed in to validate the order.
    /// @return A boolean indicating whether the order is valid. Reverts if the order has been
    /// cancelled.
    function verifyTrade(bytes32, bytes calldata payload) internal view virtual returns (bool) {
        (GnosisSafe safe, bytes32 domainSeparator, bytes32 digest) = safeLookup(payload);
        if (!isSignedConditionalOrder(safe, domainSeparator, digest)) {
            return false;
        }

        if (isCancelledConditionalOrder(safe, domainSeparator, digest)) {
            revert ConditionalOrder.OrderCancelled();
        }

        return true;
    }

    /// @dev Determine if the conditional order has been signed by the safe or not
    /// @param safe The Safe to check that is signing the order
    /// @param domainSeparator The domain separator of the Safe
    /// @param hash The hash of the order
    /// @return True if the order has been signed by the Safe
    function isSignedConditionalOrder(GnosisSafe safe, bytes32 domainSeparator, bytes32 hash)
        internal
        view
        returns (bool)
    {
        return safe.signedMessages(getMessageHashForSafe(domainSeparator, abi.encode(hash))) != 0;
    }

    /// @dev Determine if the conditional order has been cancelled by the safe or not
    /// @param safe The Safe that is cancelling the order
    /// @param domainSeparator The domain separator of the Safe
    /// @param hash The hash of the order
    /// @return True if the order has been cancelled by the Safe
    function isCancelledConditionalOrder(GnosisSafe safe, bytes32 domainSeparator, bytes32 hash)
        internal
        view
        returns (bool)
    {
        return safe.signedMessages(
            getMessageHashForSafe(
                domainSeparator, abi.encode(ConditionalOrderLib.hashCancel(hash, SETTLEMENT_DOMAIN_SEPARATOR))
            )
        ) != 0;
    }

    /// @dev Returns hash of a message that can be signed by owners. This has been copied from
    /// https://github.com/safe-global/safe-contracts/blob/5abc0bb25e7bffce8c9e53de47a392229540acf9/contracts/handler/CompatibilityFallbackHandler.sol
    /// however `safe` parameter has been replaced by the `domainSeparator` parameter. This allows for
    /// the `domainSeparator` to be cached in the calling routine, saving gas.
    /// @param domainSeparator Domain separator of the Safe.
    /// @param message Message that should be hashed
    /// @return Message hash.
    function getMessageHashForSafe(bytes32 domainSeparator, bytes memory message) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                domainSeparator,
                keccak256(abi.encode(SAFE_MSG_TYPEHASH, keccak256(message)))
            )
        );
    }

    /// @dev Returns the Gnosis Safe, domain separator and hash of the order
    /// @param order The order to be hashed
    /// @return The Gnosis Safe, domain separator and hash of the order
    function safeLookup(bytes memory order) internal view returns (GnosisSafe, bytes32, bytes32) {
        GnosisSafe safe = GnosisSafe(payable(msg.sender));
        return (safe, safe.domainSeparator(), ConditionalOrderLib.hash(order, SETTLEMENT_DOMAIN_SEPARATOR));
    }
}
