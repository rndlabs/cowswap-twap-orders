// SPDX-License-Identifier: LGPL-3.0-or-later

/* solhint-disable max-line-length */
// Vendored with minor modifications:
// - import paths
// - solidity version
// - linter config fixes
// Original source:
// <https://github.com/cowprotocol/contracts/blob/d043b0bfac7a09463c74dfe1613d0612744ed91c/src/contracts/interfaces/GPv2Authentication.sol>

pragma solidity ^0.8;

/// @title Gnosis Protocol v2 Authentication Interface
/// @author Gnosis Developers
interface GPv2Authentication {
    /// @dev determines whether the provided address is an authenticated solver.
    /// @param prospectiveSolver the address of prospective solver.
    /// @return true when prospectiveSolver is an authenticated solver, otherwise false.
    function isSolver(address prospectiveSolver) external view returns (bool);
}
