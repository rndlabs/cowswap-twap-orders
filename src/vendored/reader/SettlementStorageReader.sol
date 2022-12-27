// SPDX-License-Identifier: LGPL-3.0-or-later

/* solhint-disable max-line-length */
// Vendored with minor modifications:
// - solidity version
// - remove abicoder v2 pragma
// - linter config fixes
// Original source:
// <https://github.com/cowprotocol/contracts/blob/d043b0bfac7a09463c74dfe1613d0612744ed91c/src/contracts/reader/SettlementStorageReader.sol>

pragma solidity ^0.8;

/// @title Gnosis Protocol v2 Settlement Storage Reader
/// @author Gnosis Developers
contract SettlementStorageReader {
    // Storage Reader must have the same storage layout as the contract it reads.
    // This sneaky storage member is inherited through ReentrancyGuard
    uint256 private _status;

    mapping(bytes => uint256) public preSignature;
    mapping(bytes => uint256) public filledAmount;

    function filledAmountsForOrders(bytes[] calldata orderUids)
        public
        view
        returns (uint256[] memory filledAmounts)
    {
        filledAmounts = new uint256[](orderUids.length);
        for (uint256 i = 0; i < orderUids.length; i++) {
            filledAmounts[i] = filledAmount[orderUids[i]];
        }
    }
}