// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

// TODO: Analyse gas usage of assembly vs. abi.encodePacked in hash()

import {IERC20, IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";

import {GPv2Order} from "cowprotocol/libraries/GPv2Order.sol";

import {ConditionalOrder} from "../interfaces/ConditionalOrder.sol";
import {ConditionalOrderLib} from "../libraries/ConditionalOrderLib.sol";
import {TWAPOrderMathLib} from "./TWAPOrderMathLib.sol";

library TWAPOrder {
    using SafeCast for uint256;

    // --- structs

    struct Data {
        IERC20 sellToken;
        IERC20 buyToken;
        address receiver;
        uint256 totalSellAmount; // total amount of sellToken to sell
        uint256 maxPartLimit; // max price to pay for a unit of buyToken denominated in sellToken
        uint32 t0;
        uint32 n;
        uint32 t;
        uint32 span;
    }

    /// @dev Update this if the TWAP bundle struct changes (32 * 9).
    uint256 constant TWAP_ORDER_BYTES_LENGTH = 288;

    // --- constants

    /// @dev keccak256("conditionalorder.twap")
    bytes32 private constant APP_DATA = bytes32(0x6a1cb2f57824a1985d4bd2c556f30a048157ee9973efc0a4714604dde0a23104);

    // --- functions

    function validate(Data memory self) internal pure {
        require(self.sellToken != self.buyToken, "TWAP tokens must be different");
        require(address(self.sellToken) != address(0) && address(self.buyToken) != address(0), "TWAP tokens must be non-zero");
        require(self.totalSellAmount % self.n == 0, "TWAP totalSellAmount must be divisible by n");
        require(self.maxPartLimit > 0, "TWAP maxPartLimit must be greater than 0");
        require(self.n > 1, "TWAP n must be greater than 1");
        require(self.t > 0, "TWAP t must be greater than 0");
        require(self.span <= self.t, "TWAP span must be less than or equal to t");
    }

    function orderFor(Data memory self) internal view returns (GPv2Order.Data memory order) {
        // Check the order is valid (returning a `validTo` if so)
        uint256 validTo = TWAPOrderMathLib.calculateValidTo(
            block.timestamp,
            self.t0,
            self.n,
            self.t,
            self.span
        );

        uint256 partLimit = TWAPOrderMathLib.calculatePartLimit(
            self.totalSellAmount,
            self.n,
            self.maxPartLimit,
            IERC20Metadata(address(self.sellToken)).decimals()
        );

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
