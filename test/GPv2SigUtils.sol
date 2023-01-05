// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "../src/vendored/libraries/GPv2Order.sol";

/// @title GPv2 Signature Utilities for testing purposes
/// @author mfw78 <mfw78@rndlabs.xyz>
contract GPv2SigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    /// @dev Initializes the domain separator for EIP-712 typed data hashing.
    constructor(bytes32 _DOMAIN_SEPARATOR) {
        DOMAIN_SEPARATOR = _DOMAIN_SEPARATOR;
    }

    /// @dev The EIP-712 struct hash of an order.
    /// @param order The order data to hash.
    function getOrderStructHash(GPv2Order.Data memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                GPv2Order.TYPE_HASH,
                order.sellToken,
                order.buyToken,
                order.receiver,
                order.sellAmount,
                order.buyAmount,
                order.validTo,
                order.appData,
                order.feeAmount,
                order.kind,
                order.partiallyFillable,
                order.sellTokenBalance,
                order.buyTokenBalance
            )
        );
    }

    /// @dev Encode the order data as an EIP-712 typed data hash.
    /// @param _order The order data to encode.
    /// @return orderHash The EIP-712 typed data hash of the order data.
    function getTypedDataHash(GPv2Order.Data memory _order) 
        public
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    getOrderStructHash(_order)
                )
            );
    }

}