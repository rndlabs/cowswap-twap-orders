// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {IERC20} from "../src/vendored/interfaces/IERC20.sol";
import {GPv2Order} from "../src/vendored/libraries/GPv2Order.sol";
import {GPv2Trade} from "../src/vendored/libraries/GPv2Trade.sol";
import {GPv2Interaction} from "../src/vendored/libraries/GPv2Interaction.sol";
import {GPv2Signing} from "../src/vendored/mixins/GPv2Signing.sol";

import "./libraries/GPv2SigUtils.sol";
import "../src/CoWTWAPFallbackHandler.sol";
import "./libraries/TestAccountLib.sol";

import {Base} from "./Base.t.sol";

contract CoWProtocolSettlement is Base {
    using GPv2Order for GPv2Order.Data;
    using GPv2Trade for GPv2Order.Data;
    using GPv2SigUtils for GPv2Order.Data;
    using TestAccountLib for TestAccount;

    function testSettlement() public {
        // Let's initially make it easy. We have a single batch with two trades.
        // Alice wants to sell 100 T0 for 100 T1.
        // Bob wants to buy 100 T0 for 100 T1.

        // first we need to approve the vault relayer to spend our tokens
        vm.prank(alice.addr);
        token0.approve(relayer, 100e18);
        vm.prank(bob.addr);
        token1.approve(relayer, 100e18);

        // now we can create the orders

        // Alice's order
        GPv2Order.Data memory aliceOrder = GPv2Order.Data({
            sellToken: token0,
            buyToken: token1,
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
            sellToken: token1,
            buyToken: token0,
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
            aliceSignature = alice.signPacked(
                aliceOrder.getTypedDataHash(settlement.domainSeparator())
            );

            bobSignature = bob.signPacked(
                bobOrder.getTypedDataHash(settlement.domainSeparator())
            );
        }

        // first declare the tokens we will be trading
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        // second declare the clearing prices
        uint256[] memory clearingPrices = new uint256[](2);
        clearingPrices[0] = 1e18;
        clearingPrices[1] = 1e18;

        // third declare the trades
        GPv2Trade.Data[] memory trades = new GPv2Trade.Data[](2);

        // Alice's trade
        uint256 aliceFlags = GPv2Trade.encodeFlags(aliceOrder, GPv2Signing.Scheme.Eip712);
        console.log("aliceFlags: %s", aliceFlags);
        trades[0] = GPv2Trade.Data({
            sellTokenIndex: 0,
            buyTokenIndex: 1,
            receiver: address(0),
            sellAmount: 100e18,
            buyAmount: 100e18,
            validTo: 0xffffffff,
            appData: 0,
            feeAmount: 0,
            flags: aliceOrder.encodeFlags(GPv2Signing.Scheme.Eip712),
            executedAmount: 100e18,
            signature: aliceSignature
        });

        // Bob's trade
        uint256 bobFlags = GPv2Trade.encodeFlags(bobOrder, GPv2Signing.Scheme.Eip712);
        console.log("bobFlags: %s", bobFlags);
        trades[1] = GPv2Trade.Data({
            sellTokenIndex: 1,
            buyTokenIndex: 0,
            receiver: address(0),
            sellAmount: 100e18,
            buyAmount: 100e18,
            validTo: 0xffffffff,
            appData: 0,
            feeAmount: 0,
            flags: bobOrder.encodeFlags(GPv2Signing.Scheme.Eip712),
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
        vm.prank(solver);
        settlement.settle(tokens, clearingPrices, trades, interactions);
    }
}
