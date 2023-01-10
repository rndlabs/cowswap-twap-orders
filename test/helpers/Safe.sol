// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Enum} from "../../lib/safe/contracts/common/Enum.sol";
import {GnosisSafe} from "../../lib/safe/contracts/GnosisSafe.sol";
import {GnosisSafeProxy} from "../../lib/safe/contracts/proxies/GnosisSafeProxy.sol";
import {GnosisSafeProxyFactory} from "../../lib/safe/contracts/proxies/GnosisSafeProxyFactory.sol";
import {CompatibilityFallbackHandler} from "../../lib/safe/contracts/handler/CompatibilityFallbackHandler.sol";
import {MultiSend} from "../../lib/safe/contracts/libraries/MultiSend.sol";
import {SignMessageLib} from "../../lib/safe/contracts/libraries/SignMessageLib.sol";

import "../libraries/TestAccountLib.sol";

/// @title Safe - A helper contract for local integration testing with Gnosis Safe.
/// @author mfw78 <mfw78@rndlabs.xyz>
abstract contract Safe {
    using TestAccountLib for TestAccount[];
    using TestAccountLib for TestAccount;

    GnosisSafe public singleton;
    GnosisSafeProxyFactory public factory;
    CompatibilityFallbackHandler private handler;
    MultiSend public multisend;
    SignMessageLib public signMessageLib;

    constructor() {
        // Deploy the contracts
        singleton = new GnosisSafe();
        factory = new GnosisSafeProxyFactory();
        handler = new CompatibilityFallbackHandler();
        multisend = new MultiSend();
        signMessageLib = new SignMessageLib();
    }

    /// @dev Creates a new Gnosis Safe proxy with the provided owners and
    /// threshold.
    /// @param owners The list of owners of the Gnosis Safe.
    /// @param threshold The number of owners required to confirm a transaction.
    /// @return safe The Gnosis Safe proxy.
    function createSafe(address[] memory owners, uint256 threshold)
        internal
        returns (GnosisSafeProxy)
    {
        return GnosisSafeProxy(
            factory.createProxyWithNonce(
                address(singleton),
                abi.encodeWithSelector(
                    GnosisSafe.setup.selector,
                    owners,
                    threshold,
                    address(0),
                    "",
                    address(0),
                    address(0),
                    0,
                    address(0)
                ),
                0 // nonce
            )
        );
    }

    // @dev Executes a transaction on a Gnosis Safe proxy with the provided accounts as signatories.
    // @param safe The Gnosis Safe proxy.
    // @param to The address to which the transaction is sent. If set to 0x0, the transaction is sent to the Safe.
    // @param value The amount of Ether to be sent with the transaction.
    // @param data The data to be sent with the transaction.
    // @param operation The operation to be performed.
    // @param signers The accounts that will sign the transaction.    
    function execute(
        GnosisSafe safe,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        TestAccount[] memory signers
    ) internal {
        uint256 nonce = safe.nonce();
        bytes32 setHandlerTx = safe.getTransactionHash(
            to, 
            value,
            data,
            operation,
            0,
            0,
            0,
            address(0),
            address(0),
            nonce
        );

        // sign the transaction by alice and bob (sort their account by ascending order)
        signers = signers.sortAccounts();

        bytes memory signatures;
        for (uint256 i = 0; i < signers.length; i++) {
            signatures = abi.encodePacked(signatures, signers[i].signPacked(setHandlerTx));
        }

        // execute the transaction
        safe.execTransaction(
            to, 
            value,
            data,
            operation,
            0,
            0,
            0,
            address(0),
            payable(0),
            abi.encodePacked(signatures)
        );
    }
}