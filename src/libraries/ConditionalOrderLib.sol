// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {
    CONDITIONAL_ORDER_TYPE_HASH,
    CANCEL_ORDER_TYPE_HASH,
    ConditionalOrder
} from "../interfaces/ConditionalOrder.sol";
import {GnosisSafe} from "safe/GnosisSafe.sol";
import {SafeSigUtils} from "./SafeSigUtils.sol";

/// @title Conditional Order Library
/// @author mfw78 <mfw78@rndlabs.xyz>
library ConditionalOrderLib {
    using SafeSigUtils for bytes;

    /// @dev Get the EIP-712 TypedData hash for an order.
    /// @param payload The implementation specific conditional order to `structHash`.
    /// @param domainSeparator The settlement contract's EIP-712 domain separator to use.
    /// @return digest The ConditionalOrder's TypedData hash for signing by an EOA or EIP-1271 wallet.
    function hash(bytes memory payload, bytes32 domainSeparator) 
        internal
        pure
        returns (bytes32 digest)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        CONDITIONAL_ORDER_TYPE_HASH,
                        keccak256(payload)
                    )
                )
            )
        );
    }

    /// @dev Get the EIP-712 TypedData hash for an order.
    /// @param order The implementation specific conditional order to `structHash`.
    /// @param domainSeparator The settlement contract's EIP-712 domain separator to use.
    /// @return digest The ConditionalOrder's TypeData hash for cancelling by an EOA or EIP-1271 wallet.
    function hashCancel(bytes32 order, bytes32 domainSeparator)
        internal
        pure
        returns (bytes32 digest)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        CANCEL_ORDER_TYPE_HASH,
                        order
                    )
                )
            )
        );
    }

    /// @dev Determine if the conditional order has been signed and not cancelled
    /// @param payload The ABI encoded implementation agnostic payload to `structHash` for.
    /// @param safe The Gnosis Safe to check for a signature.
    /// @param settlementDomainSeparator The EIP-712 domain separator (of the settlement contract) to use.
    /// @return conditionalOrderHashStruct The TypedData has of the conditional order.
    function onlySignedAndNotCancelled(
        bytes memory payload,
        GnosisSafe safe,
        bytes32 settlementDomainSeparator
    ) internal view returns (bytes32) {
        bytes32 conditionalOrderHashStruct = hash(payload, settlementDomainSeparator);
        bytes32 safeDomainSeparator = safe.domainSeparator();

        /// @dev Determine if the conditional order has been signed by the Safe
        bytes32 messageHash = abi.encode(conditionalOrderHashStruct).getMessageHash(safeDomainSeparator);

        if (!SafeSigUtils.isSigned(messageHash, safe)) {
            revert ConditionalOrder.OrderNotSigned();
        }

        /// @dev Determine if the conditional order has been cancelled by the Safe
        bytes32 cancelMessageHash = abi.encode(
            hashCancel(conditionalOrderHashStruct, settlementDomainSeparator)
        ).getMessageHash(safeDomainSeparator);

        if (SafeSigUtils.isSigned(cancelMessageHash, safe)) {
            revert ConditionalOrder.OrderCancelled();
        }

        return conditionalOrderHashStruct;
    }
}