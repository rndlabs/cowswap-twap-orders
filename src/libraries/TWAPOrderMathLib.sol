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

        unchecked {
            /// @dev Order is not valid before the start (order commences at `t0`).
            if (!(startTime <= currentTime)) revert ConditionalOrder.OrderNotValid();
            /// @dev Order is expired after the last part (`n` parts, running at `t` time length).
            ///      As `startTime` is bounded by `currentTime` which is bounded by `block.timestamp`
            ///      we can safely add the `numParts * frequency` without risk of overflow.
            if (!(currentTime < startTime + (numParts * frequency))) revert ConditionalOrder.OrderExpired();

            /// @dev We use integer division to get the part number as we want to round down to the nearest part.
            ///      This is safe as we have already checked that `currentTime` < `startTime + (numParts * frequency)`.
            ///      Due to this check, we know that the part number will always be less than the total number of parts.
            uint256 part = (currentTime - startTime) / frequency;
            // calculate the `validTo` timestamp (inclusive as per `GPv2Order`)
            if (span == 0) {
                /// @dev If the span is zero, then the order is valid for the entire part.
                ///      We can safely add `part + 1` to `part` as we know that `part` is less than `numParts`.
                return startTime + ((part + 1) * frequency) - 1;
            }

            /// @dev If the span is non-zero, then the order is valid for the span of the part.
            validTo = startTime + (part * frequency) + span - 1;

            /// @dev Order is not valid if not within nominated span
            if (!(currentTime <= validTo)) revert ConditionalOrder.OrderNotValid();
        }
    }
}