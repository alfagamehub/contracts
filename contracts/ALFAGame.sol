// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Project domain: alfagame.xyz
contract ALFAGame is ERC20 {

    constructor(address initialHolder) ERC20("ALFA Game", "ALFA") {
        /// Mint 10 billion to initial holder
        _mint(initialHolder, 10_000_000_000 * 10**18);
    }

}
