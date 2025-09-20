// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../store/interfaces/IPancakeRouter.sol";

/// @title MockPancakeRouter
/// @notice Simple router mock that returns preconfigured rates for pairs along a given path.
/// @dev Store rational rates as (numerator, denominator) per directed edge tokenIn->tokenOut:
///      amountOut = amountIn * num / den. For symmetric pricing set both directions.
contract MockPancakeRouter is IPancakeRouter {
    struct Rate {
        uint256 num; // numerator
        uint256 den; // denominator
    }

    // tokenIn => tokenOut => rate
    mapping(address => mapping(address => Rate)) public rate;

    event RateSet(address indexed tokenIn, address indexed tokenOut, uint256 num, uint256 den);

    /// @notice Set rate for a directed pair tokenIn->tokenOut
    /// @param tokenIn  Input token
    /// @param tokenOut Output token
    /// @param num      Numerator in the fraction
    /// @param den      Denominator in the fraction (must be > 0)
    function setRate(address tokenIn, address tokenOut, uint256 num, uint256 den) external {
        require(den != 0, "DEN=0");
        rate[tokenIn][tokenOut] = Rate({num: num, den: den});
        emit RateSet(tokenIn, tokenOut, num, den);
    }

    /// @notice Batch set for convenience
    function setRates(address[] calldata ins, address[] calldata outs, uint256[] calldata nums, uint256[] calldata dens) external {
        require(ins.length == outs.length && ins.length == nums.length && nums.length == dens.length, "LEN");
        for (uint256 i; i < ins.length; i++) {
            setRate(ins[i], outs[i], nums[i], dens[i]);
        }
    }

    /// @inheritdoc IPancakeRouter
    function getAmountsOut(uint amountIn, address[] calldata path)
    external
    view
    override
    returns (uint[] memory amounts)
    {
        require(path.length >= 2, "PATH");
        amounts = new uint[](path.length);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < path.length - 1; i++) {
            Rate memory r = rate[path[i]][path[i + 1]];
            require(r.den != 0, "NO_RATE");
            // amountOut = amountIn * num / den
            amounts[i + 1] = amounts[i] * r.num / r.den;
        }
    }
}