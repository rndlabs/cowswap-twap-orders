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

    constructor(GPv2Settlement _settlementContract) CoWFallbackHandler(_settlementContract) {}

    /// @inheritdoc CoWFallbackHandler
    /// @dev Apply specific TWAP order validation.
    function dispatch(bytes calldata payload) public override(CoWFallbackHandler) {
        TWAPOrder.Data memory twap = abi.decode(payload, (TWAPOrder.Data));
        require(twap.sellToken != twap.buyToken, "TWAP tokens must be different");
        require(address(twap.sellToken) != address(0) && address(twap.buyToken) != address(0), "TWAP tokens must be non-zero");
        require(twap.totalSellAmount % twap.n == 0, "TWAP totalSellAmount must be divisible by n");
        require(twap.maxPartLimit > 0, "TWAP maxPartLimit must be greater than 0");
        require(twap.t0 >= block.timestamp, "TWAP t0 must be greater than or equal to current block timestamp");
        require(twap.n > 0, "TWAP n must be greater than 0");
        require(twap.t > 0, "TWAP t must be greater than 0");
        require(twap.span <= twap.t, "TWAP span must be less than or equal to t");

        /// @dev This will revert if the order isn't signed or is cancelled.
        super.dispatch(payload);
    }

    function getTradeableOrder(bytes calldata payload) external view override returns (GPv2Order.Data memory) {
        /// @dev This will revert if the order isn't signed or is cancelled.
        _onlySignedAndNotCancelled(payload);

        /// @dev Decode the payload into a TWAP bundle and get the order.
        /// `orderFor` will revert if there is no order for the current block.
        return TWAPOrder.orderFor(abi.decode(payload, (TWAPOrder.Data)));
    }

    /// @inheritdoc CoWFallbackHandler
    /// @dev This function verifies that the order hash provided in the signature
    /// matches the hash of an order that is part of the TWAP bundle. The TWAP bundle is
    /// decoded from the signature and the order is extracted from the bundle.
    /// @param _signature An ABI-encoded TWAP bundle.
    function verifyTrade(bytes32 _hash, bytes memory _signature)
        internal
        view
        override(CoWFallbackHandler)
        returns (bool)
    {
        /// @dev This will return `false` if the order isn't signed (ie. not a real order).
        /// If the order is signed, we will `revert` if the order is cancelled.
        if (!super.verifyTrade(_hash, _signature)) {
            return false;
        }

        /// @dev Get the part of the TWAP bundle after decoding it.
        GPv2Order.Data memory order = TWAPOrder.orderFor(abi.decode(_signature, (TWAPOrder.Data)));

        /// @dev The derived order hash must match the order hash provided to `isValidSignature`.
        return GPv2Order.hash(order, SETTLEMENT_DOMAIN_SEPARATOR) == _hash;
    }

    /// @inheritdoc CoWFallbackHandler
    function CONDITIONAL_ORDER_BYTES_LENGTH() internal pure override returns (uint256) {
        return _CONDITIONAL_ORDER_BYTES_LENGTH;
    }
}
