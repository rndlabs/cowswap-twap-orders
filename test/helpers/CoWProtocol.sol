// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";

import "../vendored/WETH9.sol";
import {IAuthorizer, Authorizer} from "../vendored/balancer/vault/Authorizer.sol";
import {Vault} from "../vendored/balancer/vault/Vault.sol";
import {IVault as GPv2IVault} from "../../src/vendored/interfaces/IVault.sol";
import {GPv2Settlement} from "../../src/vendored/GPv2Settlement.sol";
import {GPv2AllowListAuthentication} from "../../src/vendored/GPv2AllowListAuthentication.sol";

/// @title CoWProtocol - A helper contract for local integration testing with CoW Protocol.
/// @author mfw78 <mfw78@rndlabs.xyz>
abstract contract CoWProtocol is Test {
    // --- constants
    uint256 constant PAUSE_WINDOW_DURATION = 7776000;
    uint256 constant BUFFER_PERIOD_DURATION = 2592000;

    // --- contracts
    IWETH public weth;
    IAuthorizer public authorizer;
    GPv2IVault public vault;
    GPv2Settlement public settlement;

    // --- accounts
    address public admin;
    uint256 internal adminKey;
    address public solver;
    uint256 internal solverKey;

    address public relayer;

    constructor() {
        weth = new WETH9();
    }

    function setUp() public virtual {
        // setup test accounts
        (admin, adminKey) = makeAddrAndKey("admin");
        (solver, solverKey) = makeAddrAndKey("solver");

        authorizer = new Authorizer(admin);

        // deploy the Balancer vault
        // parameters taken from mainnet initialization:
        //   Arg [0] : authorizer (address): 0xA331D84eC860Bf466b4CdCcFb4aC09a1B43F3aE6
        //   Arg [1] : weth (address): 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        //   Arg [2] : pauseWindowDuration (uint256): 7776000
        //   Arg [3] : bufferPeriodDuration (uint256): 2592000
        vault = GPv2IVault(
            address(
                new Vault(
                    authorizer,
                    weth,
                    PAUSE_WINDOW_DURATION,
                    BUFFER_PERIOD_DURATION
                )
            )
        );

        // deploy the allow list manager
        GPv2AllowListAuthentication allowList = new GPv2AllowListAuthentication();
        allowList.initializeManager(admin);

        settlement = new GPv2Settlement(
            allowList,
            vault
        );

        relayer = address(settlement.vaultRelayer());

        // authorize the solver
        vm.prank(admin);
        allowList.addSolver(solver);
    }
}