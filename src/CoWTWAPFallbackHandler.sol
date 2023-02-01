// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GPv2Order} from "cowprotocol/libraries/GPv2Order.sol";

import {ConditionalOrder} from "./interfaces/ConditionalOrder.sol";
import {TWAPOrder} from "./libraries/TWAPOrder.sol";
import {CoWFallbackHandler} from "./CoWFallbackHandler.sol";

/// @title CoW TWAP Fallback Handler
/// @author mfw78 <mfw78@rndlabs.xyz>
/// @dev A fallback handler to enable TWAP conditional orders on Safe, settling via CoW Protocol.
contract CoWTWAPFallbackHandler is CoWFallbackHandler {
    constructor(address _settlementContract) CoWFallbackHandler(_settlementContract) {}

    /// @inheritdoc CoWFallbackHandler
    /// @dev Apply specific TWAP order validation.
    function dispatch(bytes calldata payload) public override(CoWFallbackHandler) {
        /// @dev This will revert if the TWAP bundle is invalid.
        TWAPOrder.validate(abi.decode(payload, (TWAPOrder.Data)));

        /// @dev This will revert if the conditional order isn't signed or is cancelled.
        super.dispatch(payload);
    }

    function getTradeableOrder(bytes calldata payload) external view override returns (GPv2Order.Data memory order) {
        /// @dev This will revert if the order isn't signed or is cancelled.
        _onlySignedAndNotCancelled(payload);

        /// @dev Decode the payload into a TWAP bundle and get the order. `orderFor` will revert if
        /// there is no current valid order.
        /// NOTE: This will return an order even if the part of the TWAP bundle that is currently
        /// valid is filled. This is safe as CoW Protocol ensures that each `orderUid` is only
        /// settled once.
        order = TWAPOrder.orderFor(abi.decode(payload, (TWAPOrder.Data)));

        /// @dev Revert if the order is outside the TWAP bundle's span.
        if (!(block.timestamp <= order.validTo)) revert ConditionalOrder.OrderNotValid();
    }

    /// @inheritdoc CoWFallbackHandler
    /// @dev This function verifies that the `GPv2Order` hash provided in the signature
    /// matches the hash of a `GPv2Order` that is part of the TWAP order. The TWAP order is
    /// decoded from the signature and the `GPv2Order` is extracted from the resultant TWAP
    /// order.
    /// @param payload An ABI-encoded TWAP bundle.
    function verifyTrade(bytes32 hash, bytes calldata payload)
        internal
        view
        override(CoWFallbackHandler)
        returns (bool)
    {
        /// @dev This will return `false` if the order isn't signed (ie. not a real order).
        /// If the order is signed, we will `revert` if the order is cancelled.
        if (!super.verifyTrade(hash, payload)) {
            return false;
        }

        /// @dev Get the part of the TWAP bundle after decoding it.
        GPv2Order.Data memory order = TWAPOrder.orderFor(abi.decode(payload, (TWAPOrder.Data)));

        /// @dev The derived order hash must match the order hash provided to `isValidSignature`.
        return GPv2Order.hash(order, SETTLEMENT_DOMAIN_SEPARATOR) == hash;
    }

    /// @inheritdoc CoWFallbackHandler
    function CONDITIONAL_ORDER_BYTES_LENGTH() internal pure override returns (uint256) {
        return TWAPOrder.TWAP_ORDER_BYTES_LENGTH;
    }
}
