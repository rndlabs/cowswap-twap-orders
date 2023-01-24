// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GnosisSafe} from "safe/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "safe/proxies/GnosisSafeProxyFactory.sol";
import {CompatibilityFallbackHandler} from "safe/handler/CompatibilityFallbackHandler.sol";
import {MultiSend} from "safe/libraries/MultiSend.sol";
import {SignMessageLib} from "safe/libraries/SignMessageLib.sol";

/// @title Safe - A helper contract for local integration testing with Gnosis Safe.
/// @author mfw78 <mfw78@rndlabs.xyz>
abstract contract Safe {
    GnosisSafe public singleton;
    GnosisSafeProxyFactory public factory;
    CompatibilityFallbackHandler public handler;
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
}
