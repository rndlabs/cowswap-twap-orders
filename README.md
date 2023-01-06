# CoWSwap Smart Orders ft Safe / TWAP

This repository contains the contracts and documentation relating to TWAP Orders executed via Safe on the CoWSwap Protocol.

TWAP Orders makes use of the `EIP-1271` smart order functionality that was recently introduced into CoWSwap. To make use of this, a smart contract must implement `EIP-1271`, and also provide utility methods around handling the self-custody of funds. Safe works very well for the latter, and with some configuration, can also be made to support smart orders via `EIP-1271` from CoWSwap. 

## Environment setup

Copy the `.env.example` to `.env` and set the applicable configuration variables for the testing / deployment environment.

## Testing

Initial testing is designed to run in a forked environment, and requires access to an RPC:

```bash
forge test --fork-url <your_rpc_url>
```
