// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

// TODO: Analyse gas usage of assembly vs. abi.encodePacked in hash()

import {IERC20, IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";

import {GPv2Order} from "cowprotocol/libraries/GPv2Order.sol";

import {ConditionalOrder} from "../interfaces/ConditionalOrder.sol";
import {ConditionalOrderLib} from "../libraries/ConditionalOrderLib.sol";

library TWAPOrder {
    using SafeCast for uint256;

    // --- structs

    struct Data {
        IERC20 sellToken;
        IERC20 buyToken;
        address receiver;
        uint256 totalSellAmount;    // total amount of sellToken to sell
        uint256 maxPartLimit;       // max price to pay for a unit of buyToken denominated in sellToken
        uint256 t0;
        uint256 n;
        uint256 t;
        uint256 span;
    }

    /// @dev Update this if the TWAP bundle struct changes (32 * 9).
    uint256 constant TWAP_ORDER_BYTES_LENGTH = 288;

    // --- constants

    /// @dev keccak256("conditionalorder.twap")
    bytes32 private constant APP_DATA = bytes32(0x6a1cb2f57824a1985d4bd2c556f30a048157ee9973efc0a4714604dde0a23104);

    // --- functions

    function _validateOrder(Data memory self) internal view returns (uint256) {
        /// @dev We determine if the order is requested at a valid time, respecting
        /// the start time `t0`, the number of parts `n`, and any applicable `span`.

        // Order is not valid before the start.
        if (block.timestamp < self.t0) {
            revert ConditionalOrder.OrderNotValid();
        }

        // Order is expired after the last part.
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

    function orderFor(Data memory self) internal view returns (GPv2Order.Data memory order) {
        // Check the order is valid (returning a `validTo` if so)
        uint256 validTo = _validateOrder(self);

        // get the part to sell
        /// @dev Example we are selling 100,000 DAI in 10 parts for WETH (lots of 10,000 DAI).
        ///      A limit price of of 1500 DAI/WETH means we do not want to pay more than 1500 DAI for 1 WETH.
        ///      Therefore in each part, we require a minimum of 10,000 / 1500 = 6.666666666666666666 WETH.
        ///      Thus the partLimit is 6.666666666666666666 * 10^18 = 6666666666666666666.
        uint256 partLimit = (self.totalSellAmount / self.n) 
            * (10**IERC20Metadata(address(self.sellToken)).decimals())
            / self.maxPartLimit;

        // return the order
        order = GPv2Order.Data({
            sellToken: self.sellToken,
            buyToken: self.buyToken,
            receiver: self.receiver,
            sellAmount: self.totalSellAmount / self.n,
            buyAmount: partLimit,
            validTo: validTo.toUint32(),
            appData: APP_DATA,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }
}
