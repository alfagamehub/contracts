// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl, IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IALFAStore, LootBoxPrice, NotEnoughTokens, NotEnoughAllowance} from "./interfaces/IALFAStore.sol";
import {IALFAVault, TokenInfo} from "../vault/interfaces/IALFAVault.sol";
import {IALFALootbox, TokenType} from "../NFT/Lootbox/IALFALootbox.sol";
import {IALFAReferral, ReferralPercents} from "../referral/interfaces/IALFAReferral.sol";
import {IPancakeRouter} from "./interfaces/IPancakeRouter.sol";
import {PERCENT_PRECISION} from "../const.sol";

/// @title ALFA Store
/// @notice Sells ALFA Lootboxes for USDT-equivalent prices, accepts payments in ERC20 tokens or native BNB, and distributes revenue between referrals, the team, and the vault.
/// @dev Prices are stored in USDT units (raw decimals as on BSC). Quotes for other tokens are obtained via PancakeSwap V2 router.
contract ALFAStore is AccessControl, IALFAStore {

    IALFAVault public immutable vault;
    IALFALootbox public immutable lootBox;
    IALFAReferral private immutable _referral;

    address private constant PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // V2 Router mainnet BSC
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant USDT = 0x55d398326f99059fF775485246999027B3197955; // Binance-Peg USDT

    IPancakeRouter private constant router = IPancakeRouter(PANCAKE_ROUTER);

    mapping (uint256 typeId => uint256 priceUSDT) private _prices;
    uint256 public vaultShare = 800_000;
    address public teamAccount;

    /// @notice Initializes the store with vault, lootbox, referral contracts and initial prices.
    /// @dev If `prices` is empty, a default tiered price table is set. The deployer receives DEFAULT_ADMIN_ROLE and becomes the initial team account.
    /// @param vaultAddress Address of the ALFAVault contract to receive the vault share and hold assets.
    /// @param lootBoxAddress Address of the ALFALootbox contract to mint lootboxes.
    /// @param referralAddress Address of the ALFAReferral contract used for referral distribution.
    /// @param prices Array of lootbox prices in USDT (raw token units), indexed by typeId.
    constructor(
        address vaultAddress,
        address lootBoxAddress,
        address referralAddress,
        uint256[] memory prices
        ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        teamAccount = _msgSender();

        vault = IALFAVault(vaultAddress);
        lootBox = IALFALootbox(lootBoxAddress);
        _referral = IALFAReferral(referralAddress);

        if (prices.length > 0) {
            _setPrices(prices);
        } else {
            uint256[] memory initialPrices = new uint256[](6);
            initialPrices[0] = 0;
            initialPrices[1] = 1e18;
            initialPrices[2] = 10 * 1e18;
            initialPrices[3] = 100 * 1e18;
            initialPrices[4] = 1_000 * 1e18;
            initialPrices[5] = 10_000 * 1e18;
            _setPrices(initialPrices);
        }
    }

    /// @notice Accepts native BNB transfers. Tries to forward funds to the vault; if forwarding fails, funds remain here.
    /// @dev Forwarding may fail if the vault has no payable receive/fallback. We intentionally do not revert to avoid breaking user transfers.
    receive() external payable {
        (bool sent,) = address(vault).call{value: msg.value}("");
        // If the vault has no payable receive/fallback, keep funds in the store to avoid reverting user transfers.
        if (!sent) {
            // no-op; funds remain in this contract
        }
    }


    /// Read methods

    /// @notice Returns a matrix of lootbox prices for all token types in all accepted tokens.
    /// @dev Rows correspond to lootbox typeId, columns correspond to tokens returned by `vault.getVaultTokens()`.
    ///      Each cell is the quoted amount of a token needed to pay the USDT-denominated price for that lootbox type.
    /// @return lootBoxPrice A 2D array [typeId][tokenIndex] with token address, typeId and amount.
    function getPrices() public view returns (LootBoxPrice[][] memory) {
        TokenInfo[] memory tokens = vault.getVaultTokens();
        LootBoxPrice[][] memory lootBoxPrice = new LootBoxPrice[][](lootBox.getTypes().length);

        for (uint256 i; i < lootBoxPrice.length; i++) {
            lootBoxPrice[i] = new LootBoxPrice[](tokens.length);

            for (uint256 t; t < tokens.length; t++) {
                lootBoxPrice[i][t].typeId = i + 1;
                lootBoxPrice[i][t].tokenAddress = tokens[t].tokenAddress;
                if (tokens[t].tokenAddress == address(0)) {
                    lootBoxPrice[i][t].amount = _quoteBNBForUSDT(_prices[i + 1]);
                } else {
                    lootBoxPrice[i][t].amount = _quoteTokenForUSDT(tokens[t].tokenAddress, _prices[i + 1]);
                }
            }
        }
        return lootBoxPrice;
    }


    /// Write methods

    /// @notice Buys lootboxes with an ERC20 token and optional referral parents chain.
    /// @dev Uses PancakeSwap quotes from USDT to `tokenAddress`. Performs referral/ team/ vault distribution via `_distributePayment`.
    /// @param typeId Lootbox type identifier.
    /// @param tokenAddress Payment token address (must be allowed by the vault).
    /// @param boxAmount Number of lootboxes to buy (must be > 0).
    /// @param parents Referral chain (closest parent first). May be empty.
    /// @return tokenId Array of minted lootbox token IDs.
    function buy(uint256 typeId, address tokenAddress, uint256 boxAmount, address[] memory parents) public returns (uint256[] memory) {
        _updateReferralSequence(parents);
        return _buy(typeId, tokenAddress, boxAmount);
    }

    /// @notice Buys lootboxes with native BNB and optional referral parents chain.
    /// @dev Quotes USDT price to BNB via PancakeSwap and distributes payment accordingly. Excess BNB is refunded to the buyer; if refund fails, it is forwarded to the vault.
    /// @param typeId Lootbox type identifier.
    /// @param boxAmount Number of lootboxes to buy (must be > 0).
    /// @param parents Referral chain (closest parent first). May be empty.
    /// @return tokenId Array of minted lootbox token IDs.
    function buy(uint256 typeId, uint256 boxAmount, address[] memory parents) public payable returns (uint256[] memory) {
        _updateReferralSequence(parents);
        return _buy(typeId, address(0), boxAmount);
    }


    /// Admin methods


    /// @notice Sets USDT-denominated prices per lootbox type.
    /// @dev Only callable by DEFAULT_ADMIN_ROLE. Emits `PriceSet` for each typeId.
    /// @param prices Array of prices in USDT (raw units), indexed by typeId.
    function setPrices(uint256[] memory prices) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setPrices(prices);
    }

    /// @notice Sets the store's vault share percentage (scaled by PERCENT_PRECISION).
    /// @dev Must be &lt;= 100% (PERCENT_PRECISION). The remainder after referrals and vault share is paid to the team.
    /// @param sharePercents New vault share in PERCENT_PRECISION units.
    function setVaultShare(uint256 sharePercents) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(sharePercents <= PERCENT_PRECISION, "Share exceeds 100%");
        vaultShare = sharePercents;
        emit VaultShareSet(sharePercents);
    }

    /// @notice Updates the team payout account.
    /// @dev Only callable by DEFAULT_ADMIN_ROLE.
    /// @param accountAddress Address to receive the team part of the revenue.
    function setTeamAccount(address accountAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        teamAccount = accountAddress;
        emit TeamAccountSet(accountAddress);
    }


    /// Internal methods

    /// @notice Reverts if a non-native payment token is not allowed by the vault.
    /// @dev Native payments use `address(0)`. ERC20 tokens must be enabled in the vault.
    /// @param tokenAddress Address of the payment token (use address(0) for BNB).
    function _requireTokenAvailable(address tokenAddress) internal view {
        require(vault.getTokenAvailable(tokenAddress), "Token is not allowed");
    }

    /// @notice Internal helper to set USDT-denominated prices per typeId and emit events.
    /// @param prices Array of prices in USDT (raw units), indexed by typeId.
    function _setPrices(uint256[] memory prices) internal {
        for (uint256 i = 1; i < prices.length; i++) {
            _prices[i] = prices[i];
            emit PriceSet(i, prices[i]);
        }
    }

    /// @notice Quotes how many `tokenOut` are needed for the given USDT amount using PancakeSwap V2.
    /// @dev Tries the direct USDT→tokenOut path; if it fails, falls back to USDT→WBNB→tokenOut.
    /// @param tokenOut The output token address (use WBNB for native BNB).
    /// @param usdtAmount Amount in USDT (raw units) to convert.
    /// @return amountOut Quoted amount of `tokenOut` (raw units).
    function _quoteTokenForUSDT(address tokenOut, uint256 usdtAmount) internal view returns (uint256 amountOut) {
        if (tokenOut == USDT) {
            // 1 USDT = 1 USDT
            return usdtAmount;
        }

        // 1) Try direct USDT -> tokenOut path
        {
            address[] memory path = new address[](2);
            path[0] = USDT;
            path[1] = tokenOut;
            try router.getAmountsOut(usdtAmount, path) returns (uint[] memory amounts) {
                return amounts[1];
            } catch { /* fallback below */ }
        }

        // 2) Fallback via WBNB: USDT -> WBNB -> tokenOut
        {
            address[] memory path = new address[](3);
            path[0] = USDT;
            path[1] = WBNB;
            path[2] = tokenOut;
            uint[] memory amounts = router.getAmountsOut(usdtAmount, path);
            return amounts[2];
        }
    }

    /// @notice Quotes how much BNB (via WBNB) is needed for the given USDT amount using PancakeSwap V2.
    /// @param usdtAmount Amount in USDT (raw units) to convert.
    /// @return wbnbOut Quoted amount of WBNB (raw units), numerically equal to BNB.
    function _quoteBNBForUSDT(uint256 usdtAmount) internal view returns (uint256 wbnbOut) {
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = WBNB;
        uint[] memory amounts = router.getAmountsOut(usdtAmount, path);
        return amounts[1];
    }

    /// @notice Updates the referral sequence for the caller if provided.
    /// @dev Reverts if the sequence length exceeds the number of configured referral levels.
    /// @param parents Referral chain where parents[0] is the direct referrer; may be empty.
    function _updateReferralSequence(address[] memory parents) internal {
        if (parents.length == 0) return;
        require(parents.length <= _referral.getPercents().length, "Referral sequence is too long");
        address[] memory sequence = new address[](parents.length + 1);
        sequence[0] = _msgSender();
        for (uint256 i; i < parents.length; i++) {
            sequence[i + 1] = parents[i];
        }
        _referral.setSequence(sequence);
    }

    /// @notice Sends payment from buyer to a recipient in either native BNB or ERC20.
    /// @dev For ERC20, requires prior allowance from `from` to this contract.
    /// @param tokenAddress Payment token (address(0) for BNB).
    /// @param from Payer address (usually buyer).
    /// @param to Recipient address.
    /// @param amount Amount to transfer (raw units).
    function _send(address tokenAddress, address from, address to, uint256 amount) internal {
        if (tokenAddress == address(0)) {
            (bool sent,) = address(to).call{value: amount}("");
            require(sent, "Failed to send BNB");
        } else {
            require(IERC20(tokenAddress).transferFrom(from, to, amount), "Can't send payment token");
        }
    }

    /// @notice Distributes a payment across referral parents, team, and vault according to configured percentages.
    /// @dev Returns the remaining share after paying referrals and team, which is then sent to the vault.
    /// @param holder Buyer address used as the base of the referral chain.
    /// @param refs Referral distribution data (ordered from closest parent).
    /// @param tokenAddress Payment token (address(0) for BNB).
    /// @param amount Total payment amount to distribute (raw units).
    /// @return percentsLeft Remaining percentage (in PERCENT_PRECISION) after referral payouts, capped to `vaultShare`.
    function _distributePayment(address holder, ReferralPercents[] memory refs, address tokenAddress, uint256 amount) internal returns (uint256 percentsLeft) {
        percentsLeft = PERCENT_PRECISION;
        /// Current step refer;
        address refer = holder;
        /// Loop for all available refers;
        uint r;
        while (r < refs.length) {
            /// Current parent; Stop if there is no parents left;
            address parent = refs[r].parentAddress;
            /// Stop loop is there is no referer or he is blocked
            if (parent == address(0)) {
                break;
            }
            /// Decrease total percents
            percentsLeft -= refs[r].percents;
            /// Send tokens
            uint256 referralAmount = refs[r].percents * amount / PERCENT_PRECISION;
            _send(tokenAddress, holder, parent, referralAmount);
            emit ReferralRewardSent(holder, parent, refer, tokenAddress, referralAmount);
            /// Next loop step;
            refer = parent;
            r++;
        }

        /// Send to the team
        if (percentsLeft > vaultShare) {
            uint256 teamShareAmount = (percentsLeft - vaultShare) * amount / PERCENT_PRECISION;
            _send(tokenAddress, holder, teamAccount, teamShareAmount);
            emit TeamRewardSent(holder, teamAccount, tokenAddress, teamShareAmount);
            percentsLeft = vaultShare;
        }

        /// Send to the vault
        uint256 vaultShareAmount = percentsLeft * amount / PERCENT_PRECISION;
        _send(tokenAddress, holder, address(vault), vaultShareAmount);
        emit VaultRefilled(holder, tokenAddress, vaultShareAmount);
    }

    /// @notice Core purchase logic: validates input, computes price, collects payment, mints lootboxes, and emits events.
    /// @dev Handles both native and ERC20 payments. For native payments, refunds any excess back to the buyer (or forwards to the vault if refund fails).
    /// @param typeId Lootbox type identifier to purchase.
    /// @param tokenAddress Payment token (address(0) for BNB).
    /// @param boxAmount Number of lootboxes to buy (must be > 0).
    /// @return tokenId Array of minted lootbox token IDs.
    function _buy(uint256 typeId, address tokenAddress, uint256 boxAmount) internal returns (uint256[] memory tokenId) {
        require(boxAmount > 0, "Can't sell 0 boxes");
        require(block.timestamp < vault.unlockDate(), "Sale is not available");
        require(typeId <= lootBox.getTypes().length, "NFT type is not available");
        require(_prices[typeId] > 0, "NFT type in not on sale");
        _requireTokenAvailable(tokenAddress);
        
        /// Get initial data
        address holder = _msgSender();
        ReferralPercents[] memory refs = _referral.getReferralPercents(holder);
        uint256 price = tokenAddress == address(0)
            ? _quoteBNBForUSDT(_prices[typeId])
            : _quoteTokenForUSDT(tokenAddress, _prices[typeId]);
        price *= boxAmount;

        if (tokenAddress == address(0)) {
            /// BNB amount check
            if (msg.value < price) {
                revert NotEnoughTokens(price, msg.value);
            }
            /// Distribute payment
            _distributePayment(holder, refs, tokenAddress, price);
            /// Cashback with reminder
            uint256 reminder = msg.value - price;
            if (reminder > 0) {
                (bool reminderSent,) = holder.call{value: reminder}("");
                if (!reminderSent) {
                    address(vault).call{value: reminder}("");
                }
            }
        } else {
            /// ERC20 token amount check
            IERC20 token = IERC20(tokenAddress);
            uint256 allowance = token.allowance(holder, address(this));
            uint256 balance = token.balanceOf(holder);
            if (balance < price) {
                revert NotEnoughTokens(price, balance);
            } else if (allowance < price) {
                revert NotEnoughAllowance(price, allowance);
            }
            /// Distribute payment
            _distributePayment(holder, refs, tokenAddress, price);
        }

        /// Mint LootBoxes
        tokenId = new uint256[](boxAmount);
        for (uint256 i; i < boxAmount; i++) {
            tokenId[i] = lootBox.mint(holder, typeId);
        }
        emit LootBoxSold(holder, typeId, tokenId, tokenAddress, price);
    }

}