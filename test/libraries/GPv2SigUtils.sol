// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "../../src/vendored/libraries/GPv2Order.sol";

/// @title GPv2 Signature Utilities for testing purposes
/// @author mfw78 <mfw78@rndlabs.xyz>
library GPv2SigUtils {
    using GPv2SigUtils for GPv2Order.Data;
    /// @dev The EIP-712 struct hash of an order.
    /// @param self The order data to hash.
    /// @return orderHash The EIP-712 struct hash of the order data.
    function getOrderStructHash(GPv2Order.Data memory self) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                GPv2Order.TYPE_HASH,
                self.sellToken,
                self.buyToken,
                self.receiver,
                self.sellAmount,
                self.buyAmount,
                self.validTo,
                self.appData,
                self.feeAmount,
                self.kind,
                self.partiallyFillable,
                self.sellTokenBalance,
                self.buyTokenBalance
            )
        );
    }

    /// @dev Encode the order data as an EIP-712 typed data hash.
    /// @param self The order data to encode.
    /// @param domainSeparator The domain separator to use for the hash.
    /// @return orderHash The EIP-712 typed data hash of the order data.
    function getTypedDataHash(GPv2Order.Data memory self, bytes32 domainSeparator) 
        public
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    domainSeparator,
                    self.getOrderStructHash()
                )
            );
    }

}