// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

// TODO: Analyse gas usage of assembly vs. abi.encodePacked in hash()

import "../interfaces/ConditionalOrder.sol";
import "../libraries/ConditionalOrderLib.sol";
import {IERC20} from "../vendored/interfaces/IERC20.sol";
import {GPv2Order} from "../vendored/libraries/GPv2Order.sol";
import {SafeCast} from "../vendored/libraries/SafeCast.sol";
import {GnosisSafe} from "safe/GnosisSafe.sol";
import {SafeSigUtils} from "./SafeSigUtils.sol";

library TWAPOrder {
    using SafeCast for uint256;
    using ConditionalOrderLib for bytes;

    // --- structs

    struct Data {
        IERC20 token0;
        IERC20 token1;
        address receiver;
        uint256 amount;
        uint256 lim;
        uint256 flags;
        uint256 t0;
        uint256 n;
        uint256 t;
        uint256 span;
    }

    // --- constants

    /// @dev keccak256("conditionalorder.twap")
    bytes32 private constant APP_DATA = bytes32(0x6a1cb2f57824a1985d4bd2c556f30a048157ee9973efc0a4714604dde0a23104);

    // --- functions

    /// @dev Get the EIP-712 TypedData hash.
    /// @param self The TWAP bundle.
    /// @param domainSeparator The domain separator to use.
    /// @return twapDigest The TWAP bundle's TypedData hash for signing.
    function hash(Data memory self, bytes32 domainSeparator) internal pure returns (bytes32) {
        return abi.encode(self).hash(domainSeparator);
    }

    /// @dev Determine if the TWAP bundle has been signed and not cancelled
    /// @param self The TWAP bundle to check.
    /// @param safe The Gnosis Safe to check for a signature.
    /// @param settlementDomainSeparator The EIP-712 domain separator (of the settlement contract) to use.
    /// @return twapDigest The TWAP bundle's TypedData hash.
    function onlySignedAndNotCancelled(
        Data memory self,
        GnosisSafe safe,
        bytes32 settlementDomainSeparator
    ) internal view returns (bytes32) {
        return abi.encode(self).onlySignedAndNotCancelled(
            safe,
            settlementDomainSeparator
        );
    }

    function _kindOfOrder(Data memory self) internal pure returns (bytes32) {
        if (self.flags == 0)  {
            return GPv2Order.KIND_SELL;
        }

        return GPv2Order.KIND_BUY;
    }

    function _validateOrder(Data memory self) internal view returns (uint256) {
        /// @dev We determine if the order is requested at a valid time, respecting
        /// the start time `t0`, the number of parts `n`, and any applicable `span`.

        // Order is not valid before the start.
        if (block.timestamp < self.t0) {
            revert ConditionalOrder.OrderNotValid();
        }

        // Order is not valid after the last part.
        if (block.timestamp > self.t0 + (self.n * self.t)) {
            revert ConditionalOrder.OrderExpired();
        }

        // get the TWAP bundle part number and this corresponding `validTo`
        uint256 part = (block.timestamp - self.t0) % self.t;
        uint256 validTo = self.span == 0 
            ? self.t0 + ((part + 1) * self.t) - 1
            : self.t0 + (part * self.t) + self.span;

        // Order is not valid if not within nominated span
        if (block.timestamp > validTo) {
            revert ConditionalOrder.OrderNotValid();
        }

        return validTo;
    }

    /// @dev Calculate the part order amounts for the given order.
    /// @param self The TWAP order data.
    /// @param orderKind The kind of order to calculate the part amounts for.
    /// @return partAmount The amount of the token to buy or sell.
    /// @return partLimit The limit of the token to buy or sell.
    function _partOrder(Data memory self, bytes32 orderKind) internal pure returns (uint256, uint256) {
        // get the part to buy, or sell
        uint256 partAmount = self.amount / self.n;
        uint256 partLimit = self.amount * self.lim / self.n;

        // calculate the limit for this order (ie. how much we expect to receive of the destination token)
        return orderKind == GPv2Order.KIND_SELL
            ? (partAmount, partLimit)
            : (partLimit, partAmount);
    }

    function orderFor(Data memory self) internal view returns (GPv2Order.Data memory order) {
        // Check the order is valid (returning a `validTo` if so)
        uint256 validTo = _validateOrder(self);

        // determine the direction of the swap
        bytes32 orderKind = _kindOfOrder(self);

        // determine the respective buy / sell amounts
        (uint256 sellAmount, uint256 buyAmount) = _partOrder(self, orderKind);

        // return the order
        order = GPv2Order.Data({
            sellToken: orderKind == GPv2Order.KIND_SELL ? self.token0 : self.token1,
            buyToken: orderKind == GPv2Order.KIND_BUY ? self.token0 : self.token1,
            receiver: self.receiver,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: validTo.toUint32(),
            appData: APP_DATA,
            feeAmount: 0,
            kind: orderKind,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }
}
