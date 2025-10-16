//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPancakeRouter} from "./store/interfaces/IPancakeRouter.sol";

/// @notice Container for a token balance and its quoted value in USDT.
/// @dev All amounts are in raw on-chain units (smallest decimals) for each token.
/// @param tokenAddress The ERC-20 token contract address.
/// @param balance The holder's token balance (raw units).
/// @param priceInUSDT The quoted value of `balance` in USDT (raw units of USDT).
struct TokenBalance {
    address tokenAddress;
    uint256 balance;
    uint256 priceInUSDT;
}

/// @title Portfolio balances with USDT quotes (PancakeSwap V2, BSC)
/// @notice Fetches ERC-20 balances and quotes their value in USDT using PancakeSwap V2 routes.
/// @dev Designed for BNB Smart Chain mainnet. Quotes are instantaneous spot estimates from `IPancakeRouter.getAmountsOut`.
/// @custom:network BNB Smart Chain (BSC) mainnet
/// @custom:router PancakeSwap V2 Router at 0x10ED...024E
/// @custom:assumptions Liquidity exists on the attempted route(s); tokens adhere to ERC‑20 `balanceOf`.
/// @custom:security Quotes exclude price impact, slippage, fees, and MEV. Router calls may revert; callers should handle failures.
contract Balances {

    address private constant PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E; /// @dev PancakeSwap V2 Router (BSC mainnet).
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; /// @dev Wrapped BNB (WBNB) token address (BSC mainnet).
    address private constant USDT = 0x55d398326f99059fF775485246999027B3197955; /// @dev Binance-Peg USDT token address (BSC mainnet).
    uint256 private constant MINIMAL_OUT_AMOUNT = 100;

    /// @dev Cached interface instance for the PancakeSwap V2 Router.
    IPancakeRouter private constant router = IPancakeRouter(PANCAKE_ROUTER);

    /// @notice Returns raw ERC-20 balances for `recipient` over `tokens`.
    /// @dev If a token call fails, its balance is returned as zero.
    /// @param recipient Address whose balances are queried.
    /// @param tokens List of ERC-20 token addresses to query.
    /// @return response Array of balances in raw units, aligned with `tokens`.
    function getBalances(address recipient, address[] calldata tokens) public view returns (uint[] memory) {
        uint length = tokens.length;
        uint[] memory response = new uint[](length);
        for (uint i = 0; i < length; i++) {
            response[i] = _getTokenBalance(recipient, tokens[i]);
        }
        return response;
    }

    /// @notice Returns balances and their USDT quotes, plus the USDT total.
    /// @dev For each token, balance is fetched via `IERC20.balanceOf` and quoted to USDT via PancakeSwap routes.
    ///      If a token call fails, its balance is set to zero and excluded from the total.
    /// @param recipient Address whose balances are queried.
    /// @param tokens List of ERC-20 token addresses to query.
    /// @return response Array of {token, balance, priceInUSDT} for each input token.
    /// @return totalUSDT Sum of all `priceInUSDT` values (raw USDT units).
    function getBalancesWithPrices(address recipient, address[] calldata tokens) public view returns (TokenBalance[] memory, uint256 totalUSDT) {
        uint length = tokens.length;
        TokenBalance[] memory response = new TokenBalance[](length);
        for (uint i = 0; i < length; i++) {
            response[i].tokenAddress = tokens[i];
            response[i].balance = _getTokenBalance(recipient, tokens[i]);
            response[i].priceInUSDT = _getTokenUSDTAmount(tokens[i], response[i].balance);
            totalUSDT += response[i].priceInUSDT;
        }
        return (response, totalUSDT);
    }

    /// @notice Safe balance lookup supporting native BNB and ERC‑20 tokens.
    /// @dev If `tokenAddress == address(0)`, returns the native BNB balance of `recipient`.
    ///      ERC‑20 reads are wrapped in `try/catch` to tolerate non‑standard tokens; on failure returns 0.
    /// @param recipient The account whose balance is requested.
    /// @param tokenAddress The ERC‑20 token address or `address(0)` for native BNB.
    /// @return balance The balance in raw on‑chain units (BNB has 18 decimals).
    function _getTokenBalance(address recipient, address tokenAddress) internal view returns (uint256) {
        if (tokenAddress == address(0)) {
            return recipient.balance;
        } else {
            try IERC20(tokenAddress).balanceOf(recipient) returns (uint balance) {
                return balance;
            } catch {
                return 0;
            }
        }
    }

    /// @notice Quotes how many USDT can be obtained for `amountOut` of `tokenOut`.
    /// @dev Uses direct `tokenOut→USDT` route when available, otherwise falls back to `tokenOut→WBNB→USDT`.
    ///      For native BNB/WBNB, uses `WBNB→USDT`.
    /// @param tokenOut ERC-20 token address (use `address(0)` or `WBNB` for BNB/WBNB).
    /// @param amountOut Amount of `tokenOut` to convert (raw units).
    /// @return priceInUSDT Quoted amount of USDT (raw units) obtainable for `amountOut`.
    function _getTokenUSDTAmount(address tokenOut, uint256 amountOut) internal view returns (uint256 priceInUSDT) {
        if (amountOut < MINIMAL_OUT_AMOUNT) return 0;
        if (tokenOut == address(0) || tokenOut == WBNB) {
            return _quoteBNBForUSDT(amountOut);
        } else {
            return _quoteTokenForUSDT(tokenOut, amountOut);
        }
    }

    /// @notice Quotes how many USDT are obtained for `amountOut` units of `tokenOut`.
    /// @dev First tries the direct path `tokenOut→USDT` via `router.getAmountsOut`; if it reverts, falls back to `tokenOut→WBNB→USDT`.
    /// @param tokenOut ERC-20 token address to sell for USDT.
    /// @param amountOut Amount of `tokenOut` to sell (raw units).
    /// @return priceInUSDT Quoted USDT amount (raw units) obtainable for `amountOut`.
    function _quoteTokenForUSDT(address tokenOut, uint256 amountOut) internal view returns (uint256 priceInUSDT) {
        if (tokenOut == USDT) {
            // 1 USDT = 1 USDT
            return amountOut;
        }

        // 1) Try direct tokenOut -> USDT path
        {
            address[] memory path = new address[](2);
            path[0] = tokenOut;
            path[1] = USDT;
            try router.getAmountsOut(amountOut, path) returns (uint[] memory amounts) {
                return amounts[amounts.length - 1];
            } catch { /* fallback below */ }
        }

        // 2) Fallback via WBNB: tokenOut -> WBNB -> USDT
        {
            address[] memory path = new address[](3);
            path[0] = tokenOut;
            path[1] = WBNB;
            path[2] = USDT;
            uint[] memory amounts = router.getAmountsOut(amountOut, path);
            return amounts[amounts.length - 1];
        }
    }

    /// @notice Quotes how many USDT are obtained for `amountOut` of BNB (via WBNB).
    /// @dev Uses the path `WBNB→USDT` with `router.getAmountsOut`.
    /// @param amountOut The amount of BNB/WBNB to convert (raw 18‑decimals units).
    /// @return priceInUSDT Quoted USDT amount (raw units) obtainable for `amountOut`.
    function _quoteBNBForUSDT(uint256 amountOut) internal view returns (uint256 priceInUSDT) {
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = USDT;
        uint[] memory amounts = router.getAmountsOut(amountOut, path);
        return amounts[amounts.length - 1];
    }

}