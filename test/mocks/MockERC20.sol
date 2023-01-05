// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "solmate/tokens/ERC20.sol";

uint8 constant DECIMALS = 18;

/// @title Mock ERC20 token for testing.
contract MockERC20 is ERC20 {
    /// @dev Initializes a new mock ERC20 token. No tokens are minted, makes use instead
    /// of `vm.deal` in tests.
    /// @param name The name of the token.
    /// @param symbol The symbol of the token.
    constructor(string memory name, string memory symbol) ERC20(name, symbol, DECIMALS) {}
}