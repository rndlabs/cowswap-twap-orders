// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

// TODO: vendoring notes about bytes parameters

import "../libraries/GPv2Order.sol";

/* solhint-disable max-line-length */
interface ConditionalOrder {
    /// @dev This event is emitted by the Safe when a conditional order is created.
    /// The `address` parameter is the address of the Safe that implements the `getTradeableOrder` function
    /// The `bytes` parameter is the encoded order that is passed to the CoW Protocol API
    event ConditionalOrderCreated(address indexed, bytes);

    /// @dev This event is emitted by the Safe when a conditional order is cancelled.
    /// The `bytes32` parameter is the Safe signature hash of the order that was cancelled.
    event ConditionalOrderCancelled(bytes32 indexed);

    /// @dev Using the `payload` supplied, create a conditional order that can be posted to the CoW Protocol API. The
    ///      payload may be mutated by the function to create the order, which is then emitted as a 
    ///      `ConditionalOrderCreated` event.
    function dispatch(bytes calldata payload) external;

    /// @dev Cancel a conditional order and emit a `ConditionalOrderCancelled` event.
    /// @param order The Safe signature hash of the order to cancel
    function cancel(bytes32 order) external;

    /// @dev Get a tradeable order that can be posted to the CoW Protocol API and would pass signature validation. 
    ///      Reverts if the order condition is not met.
    /// @param payload The payload used to create the order, as emitted by the ConditionalOrderCreated event
    function getTradeableOrder(bytes calldata payload) external view returns (GPv2Order.Data memory);
}