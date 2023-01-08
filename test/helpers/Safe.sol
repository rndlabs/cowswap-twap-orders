// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GnosisSafe} from "../../lib/safe/contracts/GnosisSafe.sol";
import {GnosisSafeProxy} from "../../lib/safe/contracts/proxies/GnosisSafeProxy.sol";
import {GnosisSafeProxyFactory} from "../../lib/safe/contracts/proxies/GnosisSafeProxyFactory.sol";
import {CompatibilityFallbackHandler} from "../../lib/safe/contracts/handler/CompatibilityFallbackHandler.sol";
import {MultiSend} from "../../lib/safe/contracts/libraries/MultiSend.sol";
import {SignMessageLib} from "../../lib/safe/contracts/libraries/SignMessageLib.sol";

/// @title Safe - A helper contract for local integration testing with Gnosis Safe.
/// @author mfw78 <mfw78@rndlabs.xyz>
abstract contract Safe {
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
}