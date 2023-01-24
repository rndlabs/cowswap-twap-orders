// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Enum} from "safe/common/Enum.sol";
import {GnosisSafe} from "safe/GnosisSafe.sol";
import {GnosisSafeProxy} from "safe/proxies/GnosisSafeProxy.sol";
import {GnosisSafeProxyFactory} from "safe/proxies/GnosisSafeProxyFactory.sol";
import {CompatibilityFallbackHandler} from "safe/handler/CompatibilityFallbackHandler.sol";
import {MultiSend} from "safe/libraries/MultiSend.sol";
import {SignMessageLib} from "safe/libraries/SignMessageLib.sol";

import {GPv2Order} from "cowprotocol/libraries/GPv2Order.sol";
import {GPv2Settlement} from "cowprotocol/GPv2Settlement.sol";
import {GPv2AllowListAuthentication} from "cowprotocol/GPv2AllowListAuthentication.sol";

import {TWAPOrder} from "../src/libraries/TWAPOrder.sol";
import {CoWTWAPFallbackHandler} from "../src/CoWTWAPFallbackHandler.sol";

import {TestAccount, TestAccountLib} from "./libraries/TestAccountLib.t.sol";

import {SafeLib} from "./libraries/SafeLib.t.sol";
import {Base} from "./Base.t.sol";

contract Fork is Base {
    using TWAPOrder for TWAPOrder.Data;
    using TestAccountLib for TestAccount[];
    using TestAccountLib for TestAccount;

    CoWTWAPFallbackHandler public twapHandler;
    GnosisSafeProxy public proxy;

    IERC20 sellToken;
    IERC20 buyToken;

    /// @dev Deploys the CoWTWAPFallbackHandler contract on the current fork.
    function test_fork_deploy() public {
        sellToken = IERC20(vm.envAddress("DAI"));
        buyToken = IERC20(vm.envAddress("WETH"));

        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(MAINNET_RPC_URL);

        settlement = GPv2Settlement(payable(vm.envAddress("SETTLEMENT")));
        relayer = vm.envAddress("RELAYER");

        // Deploy the CoWTWAPFallbackHandler contract
        twapHandler = new CoWTWAPFallbackHandler(address(settlement));
    }

    function test_fork_setFallbackHandler() public {
        test_fork_deploy();

        address[] memory owners = new address[](3);
        owners[0] = alice.addr;
        owners[1] = bob.addr;
        owners[2] = carol.addr;

        factory = GnosisSafeProxyFactory(payable(vm.envAddress("SAFE_PROXY_FACTORY")));
        singleton = GnosisSafe(payable(vm.envAddress("SAFE_SINGLETON")));
        multisend = MultiSend(payable(vm.envAddress("SAFE_MULTI_SEND")));
        signMessageLib = SignMessageLib(payable(vm.envAddress("SAFE_SIGN_MESSAGE_LIB")));

        // Create a new safe
        proxy = GnosisSafeProxy(payable(SafeLib.createSafe(factory, singleton, owners, 2, address(twapHandler), 0)));

        assertEq(
            vm.load(address(proxy), 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5),
            bytes32(uint256(uint160(address(twapHandler))))
        );
    }

    function test_fork_dispatch_and_settle() public {
        // 1. setup the safe with the CoWTWAPFallbackHandler
        test_fork_setFallbackHandler();

        // 2. Define the TWAP order
        TWAPOrder.Data memory twap = TWAPOrder.Data({
            sellToken: sellToken,
            buyToken: buyToken,
            receiver: address(0),
            partSellAmount: 100000 * 10 ** 18 / 25,
            minPartLimit: uint256(100000e18) / uint256(1650),
            t0: block.timestamp,
            n: 25,
            t: 1 hours,
            span: 0
        });
        bytes memory twapBytes = abi.encode(twap);

        // 3. Give the safe & bob some tokens
        deal(address(twap.sellToken), address(proxy), twap.partSellAmount * twap.n);
        deal(address(twap.buyToken), bob.addr, twap.minPartLimit * twap.n);

        // 4. Dispatch the TWAP order
        createOrder(GnosisSafe(payable(address(proxy))), twapBytes, twap.sellToken, twap.partSellAmount * twap.n);

        // 5. Get the part of the TWAP
        GPv2Order.Data memory order = CoWTWAPFallbackHandler(address(proxy)).getTradeableOrder(twapBytes);

        // 6. Authorize the solver
        GPv2AllowListAuthentication allowList = GPv2AllowListAuthentication(vm.envAddress("ALLOW_LIST"));
        vm.prank(vm.envAddress("ALLOW_LIST_MANAGER"));
        allowList.addSolver(solver.addr);

        // 7. Settle the TWAP
        vm.prank(solver.addr);
        settlePart(proxy, order, twapBytes);
    }
}
