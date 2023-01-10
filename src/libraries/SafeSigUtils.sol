// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GnosisSafe} from "safe/GnosisSafe.sol";

library SafeSigUtils {
    //keccak256(
    //    "SafeMessage(bytes message)"
    //);
    bytes32 private constant SAFE_MSG_TYPEHASH = 0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca;

    /// @dev Returns hash of a message that can be signed by owners. This function is modified from the Gnosis 
    ///      Safe implementation, with the domain separator here as a parameter to save on SLOADs.
    /// @param message Message that should be hashed
    /// @param domainSeparator Domain separator used for the safe.
    /// @return Message hash.
    function getMessageHash(bytes memory message, bytes32 domainSeparator) internal pure returns (bytes32) {
        bytes32 safeMessageHash = keccak256(abi.encode(SAFE_MSG_TYPEHASH, keccak256(message)));
        return
            keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, safeMessageHash));
    }

    /// @dev Check if the message hash was signed by the safe.
    /// @param hash Message hash that should be signed.
    /// @param safe Safe that should have signed the message.
    function isSigned(bytes32 hash, GnosisSafe safe) internal view returns (bool) {
        return safe.signedMessages(hash) != 0;
    }

}