// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CoWTWAPFallbackHandler} from "../src/CoWTWAPFallbackHandler.sol";
import {GnosisSafe} from "safe/GnosisSafe.sol";
import {Enum} from "safe/common/Enum.sol";
import {FallbackManager} from "safe/base/FallbackManager.sol";
import {SignMessageLib} from "safe/libraries/SignMessageLib.sol";
import {MultiSend} from "safe/libraries/MultiSend.sol";

import {TWAPOrder} from "../src/libraries/TWAPOrder.sol";
import {ConditionalOrderLib} from "../src/libraries/ConditionalOrderLib.sol";

import {CoWTWAPFallbackHandler} from "../src/CoWTWAPFallbackHandler.sol";

address constant FALLBACK_HANDLER = 0x87b52eD635DF746cA29651581B4d87517AAa9a9F;     // deployer cow twap fallback handler

bytes32 constant DOMAIN_SEPARATOR = 0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943; // settlement domain separator

contract DaughterSafeTWAP is Script {

    address TARGET_SAFE = vm.envAddress("TARGET_SAFE");
    uint256 TOTAL_SELL_AMOUNT = vm.envUint("TWAP_TOTAL_SELL_AMOUNT");
    uint256 TOTAL_MIN_BUY_AMOUNT = vm.envUint("TWAP_TOTAL_MIN_BUY_AMOUNT");
    uint256 TWAP_NUM_PARTS = vm.envUint("TWAP_NUM_PARTS");

    IERC20 TWAP_SELL_TOKEN = IERC20(vm.envAddress("TWAP_SELL_TOKEN"));

    function run() external {
        address SENDING_SAFE = vm.envAddress("SENDING_SAFE");

        TWAPOrder.Data memory twap = TWAPOrder.Data({
            sellToken: TWAP_SELL_TOKEN,
            buyToken: IERC20(vm.envAddress("TWAP_BUY_TOKEN")),
            receiver: address(vm.envOr("TWAP_RECEIVER", address(0))),
            partSellAmount: TOTAL_SELL_AMOUNT / TWAP_NUM_PARTS,
            minPartLimit: TOTAL_MIN_BUY_AMOUNT / TWAP_NUM_PARTS,
            t0: vm.envOr("TWAP_START_TIME", block.timestamp),
            n: TWAP_NUM_PARTS,
            t: vm.envOr("TWAP_FREQUENCY", uint256(3600)),
            span: 0
        });

        bytes memory conditionalOrder = abi.encode(twap);
        // hash of the conditional order to sign
        bytes32 typedHash = ConditionalOrderLib.hash(conditionalOrder, DOMAIN_SEPARATOR);

        bytes memory fallbackHandlerTx = abi.encodeWithSelector(
            FallbackManager.setFallbackHandler.selector,
            FALLBACK_HANDLER
        );

        bytes memory signMessageTx = abi.encodeWithSelector(SignMessageLib.signMessage.selector, abi.encode(typedHash));

        bytes memory approveTx = abi.encodeWithSelector(TWAP_SELL_TOKEN.approve.selector, vm.envAddress("RELAYER"), TOTAL_SELL_AMOUNT);

        bytes memory dispatchTx = abi.encodeWithSelector(CoWTWAPFallbackHandler(address(TARGET_SAFE)).dispatch.selector, conditionalOrder);

        // calldata to send multisend
        bytes memory cd = abi.encodeWithSelector(
            MultiSend.multiSend.selector,
            abi.encodePacked(
                // 1. sign the conditional order
                abi.encodePacked(
                    uint8(Enum.Operation.DelegateCall),
                    address(vm.envAddress("SAFE_SIGN_MESSAGE_LIB")),
                    uint256(0), // value 0
                    signMessageTx.length,
                    signMessageTx
                ),
                // 2. approve the tokens to be spent by the settlement contract
                abi.encodePacked(Enum.Operation.Call, address(TWAP_SELL_TOKEN), uint256(0), approveTx.length, approveTx),
                // 3. dispatch the conditional order
                abi.encodePacked(Enum.Operation.Call, address(TARGET_SAFE), uint256(0), dispatchTx.length, dispatchTx)
            )
        );

        // declare a 65 byte array to store the signature
        bytes memory signature = new bytes(65);
        // set the first 32 bytes to the SENDING_SAFE address and set the last byte to 1
        assembly {
            mstore(add(signature, 32), SENDING_SAFE)
            mstore8(add(signature, 96), 1)
        }

        bytes memory fallbackCd = abi.encodeWithSelector(
            GnosisSafe(payable(address(TARGET_SAFE))).execTransaction.selector,
            address(TARGET_SAFE),
            0,
            fallbackHandlerTx,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            address(0),
            signature
        );

        // get the calldata to send to the safe
        bytes memory safeCd = abi.encodeWithSelector(
            GnosisSafe(payable(address(TARGET_SAFE))).execTransaction.selector,
            address(vm.envAddress("SAFE_MULTI_SEND")),
            0,
            cd,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            address(0),
            signature
        );

        console.logString("setFallbackHandler calldata:");
        console.logBytes(fallbackCd);
        console.logString("multiSend calldata:");
        console.logBytes(safeCd);
    }
}
