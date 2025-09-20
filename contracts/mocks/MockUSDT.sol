// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MockERC20.sol";

/// @title MockUSDT
/// @notice Test USDT token; choose decimals in constructor (6 or 18 typically).
contract MockUSDT is MockERC20 {
    constructor(uint8 usdtDecimals) MockERC20("Tether USD (Mock)", "USDT", usdtDecimals) {}
}