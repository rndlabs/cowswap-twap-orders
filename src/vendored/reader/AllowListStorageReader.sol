// SPDX-License-Identifier: LGPL-3.0-or-later

/* solhint-disable max-line-length */
// Vendored with minor modifications:
// - solidity version
// - Linter config fixes
// Original source:
// <https://github.com/cowprotocol/contracts/blob/d043b0bfac7a09463c74dfe1613d0612744ed91c/src/contracts/reader/AllowListStorageReader.sol>

pragma solidity >=0.8.0 <0.9.0;

/// @title Gnosis Protocol v2 Allow List Storage Reader
/// @author Gnosis Developers
contract AllowListStorageReader {
    address private manager;
    mapping(address => bool) private solvers;

    function areSolvers(address[] calldata prospectiveSolvers)
        external
        view
        returns (bool)
    {
        for (uint256 i = 0; i < prospectiveSolvers.length; i++) {
            if (!solvers[prospectiveSolvers[i]]) {
                return false;
            }
        }
        return true;
    }
}
