# CoW Protocol Conditional Orders

This repository extends [`conditional-smart-orders`](https://github.com/cowprotocol/conditional-smart-orders), providing tight integration with [Safe](https://safe.global). It use's Safe's `SignMessageLib` to *sign* conditional orders. In doing so we:

1. Reduce conditional order creation gas costs by ~75% (for TWAPs).
2. Reduce `isValidSignature` gas costs on each settlement.

The reasoning behind using Conditional Orders with Safe is covered well on the [`conditional-smart-orders`](https://github.com/cowprotocol/conditional-smart-orders#using-smart-orders-with-your-gnosis-safe) repository, however *this* implementation of `ConditionalOrder`s provides added benefits.

Notably, the `CoWTWAPFallbackHandler` can be set on any _existing_ Safe with no loss of stock Safe functionality. This is achieved by `CoWTWAPFallbackHandler` inheriting from `CompatibilityFallbackHandler`, providing all the existing Safe functionality, and only selectively overriding and extending `isValidSignature` to achieve conditional order capabilities with CoW Protocol. `isValidSignature` still even allows for verifying signatures not related to `ConditionalOrder`s.

## Architecture

All state (excluding external on-chain data requirements as may be used by the conditional order) is stored off-chain, and passed as `bytes` (calldata) to handling functions.

Functions:
- `dispatch(bytes payload)`
- `getTradeableOrder(bytes payload)`

Event:
- `ConditionalOrderCreated(address indexed, bytes)`

Errors:
- `OrderNotValid()`
- `OrderNotSigned()`
- `OrderExpired()`
- `OrderCancelled()`

EIP-712 Types:
- `ConditionalOrder(bytes payload)`
- `CancelOrder(bytes32 order)`

### Assumptions

- CoW Protocol enforces single-use orders, ie. no `GPv2Order` can be filled more than once.

### Methodology

For the purposes of outlining the methodologies, it is assumed that the Safe has already had it's fallback handler set to that required for the implementation specific conditional order.

#### Conditional order creation

1. The conditional order is ABI-encoded to a bytes payload.
2. The payload from (1) is used as the input to generate the EIP-712 digest of `ConditionalOrder(bytes payload)`.
3. The digest from (2) is signed by the safe using a `DELEGATECALL` to `SignMessageLib`.
4. A call is made to the safe's `dispatch(bytes payload)`, passing in the payload from (1).
5. `dispatch` triggers event `ConditionalOrderCreated` that is indexed, containing the safe's address, and the payload from (1) to be used.

**CAUTION:** It is required to call `dispatch` *after* the order has been signed by the safe, otherwise the call will revert with `OrderNotSigned()`.

#### Get Tradeable Order

Conditional orders may generate one or many orders depending on their implementation. To retrieve an order that is valid at the current block:

1. Call `getTradeableOrder(bytes payload)` using the implementation specific ABI-encoded payload to get a `GPv2Order`.
2. Decoding the `GPv2Order`, use this data to populate a `POST` to the CoW Protocol API to create an order. Set the `signingScheme` to `eip1271` and the `signature` to the implementation specific ABI-encoded payload (ie. `payload`).
3. Review the order on [CoW Explorer](https://explorer.cow.fi/).
4. `getTradeableOrder(bytes payload)` may revert with one of the custom errors. This provides feedback for watch towers to modify their internal state.

#### Conditional order cancellation

1. Determine the digest for the conditional order, as discussed in [Conditional order creation](#Conditional-order-creation).
2. Generate the EIP-712 digest of `CancelOrder(bytes32 order)` where order is the digest from (1).
3. Sign the digest from (2) with the safe by using a `DELEGATECALL` TO `SignMessageLib`.

### Signing

All signatures / hashes are [EIP-712](https://eips.ethereum.org/EIPS/eip-712). The `EIP712Domain` for determing digests is that returned by `GPv2Settlement.domainSeparator()` on the relevant chain.

## Time-weighted average price (TWAP)

A simple *time-weighted average price* trade may be thought of as `n` smaller trades happening every `t` time interval, commencing at time `t0`. Additionally, it is possible to limit a part's validity of the order to a certain `span` of time interval `t`.


### Data Structure

```solidity=
struct Data {
    IERC20 sellToken;
    IERC20 buyToken;
    address receiver; // address(0) if the safe
    uint256 partSellAmount; // amount to sell in each part
    uint256 minPartLimit; // minimum buy amount in each part (limit)
    uint256 t0;
    uint256 n;
    uint256 t;
    uint256 span;
}
```

**NOTE:** No direction of trade is specified, as for TWAP it is assumed to be a *sell* order

Example: Alice wants to sell 12,000,000 DAI for at least 7500 WETH. She wants to do this using a TWAP, executing a part each day over a period of 30 days.

* `sellToken` = DAI
* `buytoken` = WETH
* `receiver` = `address(0)`
* `partSellAmount` = 12000000 / 30 = 400000 DAI
* `minPartLimit` = 7500 / 30 = 250 WETH
* `t0` = Nominated start time (unix epoch seconds)
* `n` = 30 (number of parts)
* `t` = 86400 (duration of each part, in seconds)
* `span` = 0 (duration of `span`, in seconds, or `0` for entire interval)

If Alice also wanted to restrict the duration in which each part traded in each day, she may set `span` to a non-zero duration. For example, if Alice wanted to execute the TWAP, each day for 30 days, however only wanted to trade for the first 12 hours of each day, she would set `span` to `43200` (ie. `60 * 60 * 12`).

Using `span` allows for use cases such as weekend or week-day only trading.

### Methodology

To create a TWAP order:

1. ABI-Encode the above `Data` struct and sign it with the safe as outlined in [Conditional Order Creation](#Conditional-order-creation)
2. Approve `GPv2VaultRelayer` to trade `n x partSellAmount` of the safe's `sellToken` tokens (in the example above, `GPv2VaultRelayer` would receive approval for spending 12,000,000 DAI tokens).
3. Call `dispatch` to announce the TWAP order to the watch tower.

Fortunately, when using Safe, it is possible to batch together all the above calls to perform this step atomically, and optimise gas consumption / UX. For code examples on how to do this, please refer to the [CLI](#CLI).

**NOTE:** For cancelling a TWAP order, follow the instructions at [Conditional order cancellation](#Conditional-order-cancellation).

## CLI

The CLI utility provided contains help functions to see all the options / configurability available for each subcommand.

**CAUTION:** This utility handles private keys for proposing transactions to Safes. Standard safety precautions associated with private key handling applies. It is recommended to **NEVER** pass private keys directly via command line as this may expose sensitive keys to those who have access to list processes running on your machine.

### Enviroment setup

Copy `.env.example` to `.env`, setting at least the `PRIVATE_KEY` and `ETH_RPC_URL`. Then build the project, in the root directory of the repository:

```bash
yarn build
```

### Usage

```
Usage: conditional-orders [options] [command]

Dispatch or cancel conditional orders on Safe using CoW Protocol

Options:
  -V, --version                   output the version number
  -h, --help                      display help for command

Commands:
  create-twap [options]           Create a TWAP order
  set-fallback-handler [options]  Set the fallback handler of the Safe
  cancel-order [options]          Cancel an order
  help [options] [command]        display help for command
```

1. Setting a safe's fallback handler

   ```bash
   yarn ts-node cli.ts set-fallback-handler -s 0xdc8c452D81DC5E26A1A73999D84f2885E04E9AC3 --handler 0x87b52ed635df746ca29651581b4d87517aaa9a9f
   ```
   
   Check your safe's transaction queue and you should see the newly created transaction.

3. Creating a TWAP order

   The CLI utility will automatically do some math for you. All order creation is from the perspective of _totals_. By specifying the `--sell-token`, `--buy-token`, `--total-sell-amount`, and `--total-min-buyamount`, the CLI will automatically determine the number of decimals, parse the values, and divide the totals by the number of parts (`-n`), using the results as the basis for the TWAP order.

   ```bash
   yarn ts-node cli.ts create-twap -s 0xdc8c452D81DC5E26A1A73999D84f2885E04E9AC3 --sell-token 0x91056D4A53E1faa1A84306D4deAEc71085394bC8 --buy-token 0x02ABBDbAaa7b1BB64B5c878f7ac17f8DDa169532 --total-sell-amount 1000 --total-min-buy-amount 1 -n 6 -t 600
   ```

   Check your safe' transaction queue, and you should see a newly created transaction that batches together the signing of the conditional order, approving `GPv2VaultRelayer` on `sellToken` for `total-sell-amount`, and emits the order via `dispatch`.

   **NOTE:** When creating TWAP orders, the `--total-sell-amount` and `--total-min-buy-amount` are specified in whole units of the respective ERC20 token. For example, if wanting to buy a total amount of 1 WETH, specify `--total-min-buy-amount 1`. The CLI will automatically determine decimals and specify these appropriately.

3. Cancelling a conditional order

   To cancel an order, you must know it's *order hash*, which is the EIP-712 digest of `ConditionalOrder(bytes payload)`.

   ```bash
   yarn ts-node cli.ts cancel-order -s 0xdc8c452D81DC5E26A1A73999D84f2885E04E9AC3 --order-hash 0x6070b52cef3c1a6dd0070bd7382b32418b66dc333bf36b1e7ae28f6d7b287f07
   ```
   
   Check your safe's transaction queue, and you should see a newly created transaction to cancel the conditional order.

## Tenderly Actions

A watchdog has been implementing using [Tenderly Actions](https://docs.tenderly.co/web3-actions/intro-to-web3-actions). By means of *emitted Event* and new block monitoring, conditional orders can run autonomously. 

Notably, with the `CondtionalOrderCreated` event, multiple conditional orders can be created for one safe - in doing so, the actions maintain a registry of:

1. Safes that have created _at least one conditional order_.
2. All payloads for conditional orders by safe that have not expired or been cancelled.
3. All part orders by `orderUid` containing their status (`SUBMITTED`, `FILLED`) - the `Trade` on `GPv2Settlement` is monitored to determine if an order is `FILLED`.

As orders expire, or are cancelled, they are removed from the registry to conserve storage space.

**TODO:** Improvements to flag an `orderUid` as `SUBMITTED` if the API returns an error due to duplicate order submission. This would limit queries to the CoW Protocol API to the total number of watchtowers being run.

### Local testing

From the root directory of the repository:

```bash
yarn build
yarn test:actions
```

If for some reason the watch tower hasn't picked up a conditional order, this can be simulated by calling a local version directly:

```bash
yarn build
ETH_RPC_URL=http://rpc-url-here.com:8545 yarn ts-node ./actions/test/run_local.ts <safeAddress> <payload>
```

When subsituting in the `safeAddress` and `payload`, this will simulate the watch tower, and allow for order submission if the watch tower is down.

### Deployment

If running your own watch tower, or deploying for production:

```bash
tenderly actions deploy
```

## Developers

### Requirements

* `forge` ([Foundry](https://github.com/foundry-rs/foundry))
* `node` (`>= v16.18.0`)
* `yarn`
* `npm`
* `tenderly`

### Deployed Contracts

Contracts within have been audited by Group0. [See their audit report here](./audits/Group0_CowTwapOrdersJan2023.pdf).

| Contact Name | Ethereum Mainnet | Goerli | Gnosis Chain |
| -------- | --- | --- | --- |
| `CoWTWAPFallbackHandler` | [`0x87b52ed635df746ca29651581b4d87517aaa9a9f`](https://etherscan.io/address/0x87b52ed635df746ca29651581b4d87517aaa9a9f#code) | [`0x87b52ed635df746ca29651581b4d87517aaa9a9f`](https://goerli.etherscan.io/address/0x87b52ed635df746ca29651581b4d87517aaa9a9f#code) | [`0x87b52ed635df746ca29651581b4d87517aaa9a9f`](https://gnosisscan.io/address/0x87b52ed635df746ca29651581b4d87517aaa9a9f#code) |

**NOTE:** Due to some issues between `forge` and gnosisscan, contracts are verified on sourcify, and therefore viewabled on [here on blockscout](https://blockscout.com/xdai/mainnet/address/0x87b52eD635DF746cA29651581B4d87517AAa9a9F/contracts#address-tabs) for Gnosis Chain. All other deployments are verified on their respective Etherscan-derivative block explorer.

### Environment setup

Copy the `.env.example` to `.env` and set the applicable configuration variables for the testing / deployment environment.

### Testing

Effort has been made to adhere as close as possible to [best practices](https://book.getfoundry.sh/tutorials/best-practices), with *unit*, *fuzzing* and *fork* tests being implemented.

**NOTE:** Fuzz tests also include a `simulate` that runs full end-to-end integration testing, including the ability to settle conditional orders. Fork testing simulates end-to-end against production ethereum mainnet contracts, and as such requires `ETH_RPC_URL` to be defined (this should correspond to an archive node).

```bash
forge test -vvv --no-match-test "fork|[fF]uzz" # Basic unit testing only
forge test -vvv --no-match-test "fork" # Unit and fuzz testing
forge test -vvv # Unit, fuzz, and fork testing
```

### Coverage

```bash
forge coverage -vvv --no-match-test "fork" --report summary
```

### Deployment

Deployment is handled by solidity scripts in `forge`. The network being deployed to is dependent on the `ETH_RPC_URL`.

```bash
source .env
forge script script/deploy_CoWTWAPFallbackHandler.s.sol:DeployCoWTWAPFallbackHandler --rpc-url $ETH_RPC_URL --broadcast -vvvv --verify 
```

#### Local deployment

For local integration testing, including the use of [Tenderly Actions](#Tenderly-actions), it may be useful deploying to a _forked_ mainnet environment. This can be done with `anvil`.

1. Open a terminal and run `anvil`:

   ```bash
   anvil --fork-url http://erigon.dappnode:8545
   ```
   
2. Follow the previous deployment directions, with this time specifying `anvil` as the RPC-URL:

   ```bash
   source .env
   forge script  script/deploy_CoWTWAPFallbackHandler.s.sol:DeployCoWTWAPFallbackHandler --rpc-url http://127.0.0.1:8545 --broadcast -vvvv
   ```

   **NOTE:** `--verify` is omitted as with local deployments, these should not be submitted to Etherscan for verification.
