// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/// @title Chain Fallback Handler
/// @author mfw78 <mfw78@rndlabs.xyz>
/// @dev This is an abstract contract that provides a base fallback function to pass on any fallback calls to a
/// fallback handler contract. If the fallback handler is not set, then the fallback call will be ignored.
/// Heavily inspired by Gnosis Safe's FallbackManager contract.
abstract contract ChainFallbackHandler {

    /// @dev The address of the fallback handler contract. This is a constant value that is set at compile time.
    /// This cannot be changed after deployment, any changes to the chained fallback handler contract will require a
    /// new deployment of this contract.
    address constant CHAIN_FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;

    // solhint-disable-next-line payable-fallback,no-complex-fallback
    fallback() external {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            /// @dev As the CHAIN_FALLBACK_HANDLER is a constant value, we can skip the check for the fallback handler
            /// address being zero. Code commented out below is the original code from Gnosis Safe's FallbackManager 
            // contract, and is left here for reference and ease of auditing.
            // if iszero(CHAIN_FALLBACK_HANDLER) {
            //     return(0, 0)
            // }

            calldatacopy(0, 0, calldatasize())
            // The msg.sender address is shifted to the left by 12 bytes to remove the padding
            // Then the address without padding is stored right after the calldata
            mstore(calldatasize(), shl(96, caller()))
            // Add 20 bytes for the address appended add the end
            let success := call(gas(), CHAIN_FALLBACK_HANDLER, 0, 0, add(calldatasize(), 20), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(success) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }
}
