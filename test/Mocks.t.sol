// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {GPv2AllowListAuthentication} from "../src/vendored/GPv2AllowListAuthentication.sol";
import {GPv2VaultRelayer} from "../src/vendored/GPv2VaultRelayer.sol";
import {GPv2Settlement} from "../src/vendored/GPv2Settlement.sol";
import {GPv2Order} from "../src/vendored/libraries/GPv2Order.sol";
import {GPv2Signing} from "../src/vendored/mixins/GPv2Signing.sol";
import {GPv2Trade as VendoredGPv2Trade} from "../src/vendored/libraries/GPv2Trade.sol";
import {GPv2Trade} from "./libraries/GPv2Trade.sol";
import {GPv2Interaction} from "../src/vendored/libraries/GPv2Interaction.sol";
import {IVault as VendoredVault} from "../src/vendored/interfaces/IVault.sol";
import {IERC20} from "../src/vendored/interfaces/IERC20.sol";

import "./vendored/WETH9.sol";
import "./mocks/MockERC20.sol";
import "./GPv2SigUtils.sol";
import {IAuthorizer, Authorizer} from "./vendored/balancer/vault/Authorizer.sol";
import {IVault, IWETH} from "./vendored/balancer/vault/interfaces/IVault.sol";
import {Vault} from "./vendored/balancer/vault/Vault.sol";

contract VaultRelayer is Test {
    using GPv2Order for GPv2Order.Data;

    // --- constants
    uint256 constant PAUSE_WINDOW_DURATION = 7776000;
    uint256 constant BUFFER_PERIOD_DURATION = 2592000;

    IWETH public weth;
    IAuthorizer public authorizer;
    VendoredVault public vault;
    GPv2Settlement public settlement;

    // test contracts
    GPv2SigUtils internal sigUtils;

    address public relayer;

    address admin_;
    uint256 adminKey_;

    address solver_;
    uint256 solverKey_;

    address alice;
    uint256 aliceKey;

    address bob;
    uint256 bobKey;

    IERC20 public t0;
    IERC20 public t1;
    IERC20 public t2;

    function setUp() public {
        // setup test accounts
        (admin_, adminKey_) = makeAddrAndKey("admin");
        (solver_, solverKey_) = makeAddrAndKey("solver");
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");

        // deploy WETH9
        weth = IWETH(address(new WETH9()));

        // deploy test tokens
        t0 = IERC20(address(new MockERC20("Token 0", "T0")));
        t1 = IERC20(address(new MockERC20("Token 1", "T1")));
        t2 = IERC20(address(new MockERC20("Token 2", "T2")));

        // give some tokens to alice and bob
        deal(address(t0), alice, 1000e18);
        deal(address(t1), bob, 1000e18);

        // setup the Authorizor for the Balancer Vaults
        authorizer = new Authorizer(admin_);

        // deploy the Balancer Vault
        // parameters taken from mainnet initialization:
        //   Arg [0] : authorizer (address): 0xA331D84eC860Bf466b4CdCcFb4aC09a1B43F3aE6
        //   Arg [1] : weth (address): 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        //   Arg [2] : pauseWindowDuration (uint256): 7776000
        //   Arg [3] : bufferPeriodDuration (uint256): 2592000
        vault = VendoredVault(
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
        allowList.initializeManager(admin_);

        // deploy the settlement contract
        settlement = new GPv2Settlement(allowList, vault);

        // record the relayer address
        relayer = address(settlement.vaultRelayer());

        // deploy the signature utils
        sigUtils = new GPv2SigUtils(settlement.domainSeparator());

        // authorize the solver
        vm.prank(admin_);
        allowList.addSolver(solver_);
    }

    function testSettlement() public {
        // Let's initially make it easy. We have a single batch with two trades.
        // Alice wants to sell 100 T0 for 100 T1.
        // Bob wants to buy 100 T0 for 100 T1.

        // first we need to approve the vault relayer to spend our tokens
        vm.prank(alice);
        t0.approve(relayer, 100e18);
        vm.prank(bob);
        t1.approve(relayer, 100e18);

        // now we can create the orders

        // Alice's order
        GPv2Order.Data memory aliceOrder = GPv2Order.Data({
            sellToken: t0,
            buyToken: t1,
            receiver: address(0),
            sellAmount: 100e18,
            buyAmount: 100e18,
            validTo: 0xffffffff,
            appData: 0,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        // Bob's order
        GPv2Order.Data memory bobOrder = GPv2Order.Data({
            sellToken: t1,
            buyToken: t0,
            receiver: address(0),
            sellAmount: 100e18,
            buyAmount: 100e18,
            validTo: 0xffffffff,
            appData: 0,
            feeAmount: 0,
            kind: GPv2Order.KIND_BUY,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        bytes memory aliceSignature;
        bytes memory bobSignature;

        {
            // now we can sign the orders
            (uint8 aliceV, bytes32 aliceR, bytes32 aliceS) = vm.sign(
                aliceKey,
                sigUtils.getTypedDataHash(aliceOrder)
            );

            aliceSignature = tightlyPackSignature(aliceR, aliceS, aliceV);

            (uint8 bobV, bytes32 bobR, bytes32 bobS) = vm.sign(
                bobKey,
                sigUtils.getTypedDataHash(bobOrder)
            );

            bobSignature = tightlyPackSignature(bobR, bobS, bobV);
        }

        // first declare the tokens we will be trading
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = t0;
        tokens[1] = t1;

        // second declare the clearing prices
        uint256[] memory clearingPrices = new uint256[](2);
        clearingPrices[0] = 1e18;
        clearingPrices[1] = 1e18;

        // third declare the trades
        VendoredGPv2Trade.Data[] memory trades = new VendoredGPv2Trade.Data[](2);

        // Alice's trade
        uint256 aliceFlags = GPv2Trade.encodeFlags(aliceOrder, GPv2Signing.Scheme.Eip712);
        console.log("aliceFlags: %s", aliceFlags);
        trades[0] = VendoredGPv2Trade.Data({
            sellTokenIndex: 0,
            buyTokenIndex: 1,
            receiver: address(0),
            sellAmount: 100e18,
            buyAmount: 100e18,
            validTo: 0xffffffff,
            appData: 0,
            feeAmount: 0,
            flags: GPv2Trade.encodeFlags(aliceOrder, GPv2Signing.Scheme.Eip712),
            executedAmount: 100e18,
            signature: aliceSignature
        });

        // Bob's trade
        uint256 bobFlags = GPv2Trade.encodeFlags(bobOrder, GPv2Signing.Scheme.Eip712);
        console.log("bobFlags: %s", bobFlags);
        trades[1] = VendoredGPv2Trade.Data({
            sellTokenIndex: 1,
            buyTokenIndex: 0,
            receiver: address(0),
            sellAmount: 100e18,
            buyAmount: 100e18,
            validTo: 0xffffffff,
            appData: 0,
            feeAmount: 0,
            flags: GPv2Trade.encodeFlags(bobOrder, GPv2Signing.Scheme.Eip712),
            executedAmount: 100e18,
            signature: bobSignature
        });

        // fourth declare the interactions
        GPv2Interaction.Data[][3] memory interactions = [
            new GPv2Interaction.Data[](0),
            new GPv2Interaction.Data[](0),
            new GPv2Interaction.Data[](0)
        ];

        // finally, we can execute the settlement
        vm.prank(solver_);
        settlement.settle(tokens, clearingPrices, trades, interactions);
    }

    function tightlyPackSignature(
        bytes32 r,
        bytes32 s,
        uint8 v
    ) internal pure returns (bytes memory) {
        bytes memory signature = new bytes(65);
        signature = abi.encodePacked(r, s, v);
        return signature;
    }
}
