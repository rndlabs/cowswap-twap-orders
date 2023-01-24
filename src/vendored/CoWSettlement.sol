// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/// @title Abstract interface for `GPv2Settlement` contract.
/// @author mfw78 <mfw78@rndlabs.xyz>
/// @dev This is a minimal interface for interacting with the settlement contract.
interface CoWSettlement {
    /// @dev The domain separator used for signing orders.
    /// @return The domain separator.
    function domainSeparator() external view returns (bytes32);
}
