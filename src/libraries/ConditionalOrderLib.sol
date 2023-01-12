// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GnosisSafe} from "safe/GnosisSafe.sol";

import {
    CONDITIONAL_ORDER_TYPE_HASH,
    CANCEL_ORDER_TYPE_HASH
} from "../interfaces/ConditionalOrder.sol";

/// @title Conditional Order Library
/// @author mfw78 <mfw78@rndlabs.xyz>
library ConditionalOrderLib {
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
}