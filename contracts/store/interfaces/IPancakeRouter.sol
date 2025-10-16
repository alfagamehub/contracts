// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPancakeRouter {
    function getAmountsOut(uint amountIn, address[] calldata path)
        external
        view
        returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}