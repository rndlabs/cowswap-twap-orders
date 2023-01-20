// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ConditionalOrder} from "../interfaces/ConditionalOrder.sol";

/// @title CoWProtocol TWAP Order Math Library
/// @dev Math is broken out into a library to enable easier unit testing and SMT verification.
/// @author mfw78 <mfw78@rndlabs.xyz>
library TWAPOrderMathLib {

    // --- functions

    /// @dev Calculate the `validTo` timestamp for part of a TWAP order.
    /// @param currentTime The current timestamp (ie. block.timestamp).
    /// @param startTime The start time of the TWAP order.
    /// @param numParts The number of parts to split the order into.
    /// @param frequency The frequency of each part.
    /// @param span The span of each part.
    function calculateValidTo(
        uint256 currentTime,
        uint256 startTime,
        uint256 numParts,
        uint256 frequency,
        uint256 span
    ) internal pure returns (uint256 validTo) {
        /// @dev Use `assert` to check for invalid inputs as these should be caught by the
        /// conditional order validation logic in `dispatch` before calling this function.
        /// This is to save on gas deployment costs vs using `require` statements.
        assert(numParts <= type(uint32).max);
        assert(frequency > 0 && frequency <= 365 days);
        assert(span <= frequency);

        /// @dev Order is not valid before the start (order commences at `t0`).
        if (!(startTime <= currentTime)) revert ConditionalOrder.OrderNotValid();
        /// @dev Order is expired after the last part (`n` parts, running at `t` time length).
        if (!(currentTime < startTime + (numParts * frequency))) revert ConditionalOrder.OrderExpired();

        // Get the TWAP order part number (indexed from 0)
        uint256 part;
        unchecked {
            part = (currentTime - startTime) / frequency;
        }
        // The part number MUST be less than the total number of parts (`n`)
        assert(part < numParts);
        // calculate the `validTo` timestamp (inclusive as per `GPv2Order`)
        unchecked {
            validTo = (span == 0 ? startTime + ((part + 1) * frequency) : startTime + (part * frequency) + span) - 1;
        }

        /// @dev Order is not valid if not within nominated span
        if (!(currentTime <= validTo)) revert ConditionalOrder.OrderNotValid();
    }

    /// @dev Calculate the part limit for a TWAP order.
    /// @param totalSellAmount The total amount of sellToken to sell.
    /// @param numParts The number of parts to split the order into.
    /// @param maxPartLimit The maximum part limit for the order.
    /// @param decimals The number of decimals for the sellToken.
    /// @return partLimit The part limit for the order.
    function calculatePartLimit(
        uint256 totalSellAmount,
        uint256 numParts,
        uint256 maxPartLimit,
        uint256 decimals
    ) internal pure returns (uint256 partLimit) {
        /// @dev Use `assert` to check for invalid inputs as these should be caught by the
        /// conditional order validation logic in `dispatch` before calling this function.
        assert(totalSellAmount % numParts == 0);
        assert(maxPartLimit > 0);
        assert(numParts > 0);

        /// @dev We determine the part limit for a TWAP order, which is the maximum
        /// amount of buyToken that can be bought for a unit of sellToken.

        /// @dev Example we are selling 100,000 DAI in 10 parts for WETH (lots of 10,000 DAI).
        ///      A limit price of of 1500 DAI/WETH means we do not want to pay more than 1500 DAI for 1 WETH.
        ///      Therefore in each part, we require a minimum of 10,000 / 1500 = 6.666666666666666666 WETH.
        ///      Thus the partLimit is 6.666666666666666666 * 10^18 = 6666666666666666666.
        partLimit = (totalSellAmount / numParts) * pow(10, decimals) / maxPartLimit;
    }

    /// @dev Calculate x ** n. This is required as the SMTChecker does not support exponentiation.
    /// @param x The base
    /// @param n The exponent
    function pow(uint256 x, uint256 n) internal pure returns (uint256) {
        uint256 result = 1;
        for (uint256 i = 0; i < n; i++) {
            result *= x;
        }
        return result;
    }
}