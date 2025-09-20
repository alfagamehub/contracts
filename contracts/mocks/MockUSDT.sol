// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./MockERC20.sol";

/// @title MockUSDT
/// @notice Test USDT token; choose decimals in constructor (6 or 18 typically).
contract MockUSDT is MockERC20 {
    /// @notice Initializes the mock USDT token after code injection (constructor-less).
    /// @dev Can only be called once; sets decimals to match USDT variants.
    /// @param usdtDecimals Number of decimals (6 or 18 typically).
    function initialize(uint8 usdtDecimals) public {
        require(decimals == 0, "Already initialized");
        assembly { sstore(decimals.slot, usdtDecimals) }
    }
}