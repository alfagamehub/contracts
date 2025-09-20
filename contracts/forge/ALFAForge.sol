// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl, IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IALFAForge, UpgradeChance, UpgradePrice, NotEnoughTokens} from "./IALFAForge.sol";
import {IALFAKey} from "../NFT/Key/IALFAKey.sol";
import {IALFAVault} from "../vault/interfaces/IALFAVault.sol";
import {IALFAReferral, ReferralPercents} from "../referral/interfaces/IALFAReferral.sol";
import {IPancakeRouter} from "../store/interfaces/IPancakeRouter.sol";
import {PERCENT_PRECISION} from "../const.sol";

contract ALFAForge is AccessControl, IALFAForge {

    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant EDITOR_ROLE = keccak256("EDITOR_ROLE");

    address private constant PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // V2 Router mainnet BSC
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant USDT = 0x55d398326f99059fF775485246999027B3197955; // Binance-Peg USDT

    IPancakeRouter private constant router = IPancakeRouter(PANCAKE_ROUTER);

    EnumerableSet.AddressSet private _tokens;
    mapping(address tokenAddress => uint256 tokenDiscount) private _discount;

    mapping (uint256 typeId => uint256 priceUSDT) private _prices;
    mapping(uint256 typeId => UpgradeChance[] drop) internal _typeDrop;
    IALFAKey public immutable key;
    IALFAVault public immutable vault;
    IALFAReferral private immutable _referral;

    uint256 private _randomCounter;

    address public teamAccount;
    address public burnAccount;
    uint256 public burnShare = 800_000;

    constructor(
        address keyAddress,
        address burnAccountAddress,
        address referralAddress,
        address vaultAddress
        ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(EDITOR_ROLE, _msgSender());

        teamAccount = _msgSender();
        burnAccount = burnAccountAddress;

        key = IALFAKey(keyAddress);
        vault = IALFAVault(vaultAddress);
        _referral = IALFAReferral(referralAddress);


        uint256[] memory initialPrices = new uint256[](5);
        initialPrices[0] = 0;
        initialPrices[1] = 25 * 1e17;
        initialPrices[2] = 25 * 1e18;
        initialPrices[3] = 25 * 1e19;
        initialPrices[4] = 25 * 1e20;
        _setPrices(initialPrices);

        _addDrop(1, UpgradeChance(0, 200000));
        _addDrop(1, UpgradeChance(2, 780000));
        _addDrop(1, UpgradeChance(3,  17500));
        _addDrop(1, UpgradeChance(4,   2400));
        _addDrop(1, UpgradeChance(5,    100));

        _addDrop(2, UpgradeChance(0, 400000));
        _addDrop(2, UpgradeChance(3, 560000));
        _addDrop(2, UpgradeChance(4,  39500));
        _addDrop(2, UpgradeChance(5,    500));

        _addDrop(3, UpgradeChance(0, 600000));
        _addDrop(3, UpgradeChance(4, 399000));
        _addDrop(3, UpgradeChance(5,   1000));

        _addDrop(4, UpgradeChance(0, 800000));
        _addDrop(4, UpgradeChance(5, 200000));
    }

    /// @notice Accepts native BNB transfers. Tries to forward funds to the vault; if forwarding fails, funds remain here.
    /// @dev Forwarding may fail if the vault has no payable receive/fallback. We intentionally do not revert to avoid breaking user transfers.
    receive() external payable {
        (bool sent,) = address(teamAccount).call{value: msg.value}("");
        // If the vault has no payable receive/fallback, keep funds in the store to avoid reverting user transfers.
        if (!sent) {
            // no-op; funds remain in this contract
        }
    }


    /// Read methods

    /// @notice Returns a matrix of lootbox prices for all token types in all accepted tokens.
    /// @dev Rows correspond to lootbox typeId, columns correspond to tokens returned by `vault.getVaultTokens()`.
    ///      Each cell is the quoted amount of a token needed to pay the USDT-denominated price for that lootbox type.
    /// @return upgradePrice A 2D array [typeId][priceIndex] with token address, typeId and amount.
    function getPrices() public view returns (UpgradePrice[][] memory) {
        UpgradePrice[][] memory upgradePrice = new UpgradePrice[][](key.getTypes().length - 1);

        for (uint256 i; i < upgradePrice.length; i++) {
            upgradePrice[i] = new UpgradePrice[](_tokens.length());

            for (uint256 t; t < _tokens.length(); t++) {
                upgradePrice[i][t].typeId = i + 1;
                upgradePrice[i][t].tokenAddress = _tokens.at(t);
                if (upgradePrice[i][t].tokenAddress == address(0)) {
                    upgradePrice[i][t].amount = _quoteBNBForUSDT(_prices[i]);
                } else {
                    upgradePrice[i][t].amount = _quoteTokenForUSDT(upgradePrice[i][t].tokenAddress, _prices[i]);
                }
            }
        }
        return upgradePrice;
    }

    
    /// Write methods

    function upgrade(uint256 tokenId, address tokenAddress) public returns (uint256 newItemId) {
        _pay(tokenId, tokenAddress);
        newItemId = _upgrade(tokenId);
    }

    function upgrade(uint256 tokenId) public payable returns (uint256 newItemId) {
        _pay(tokenId, address(0));
        newItemId = _upgrade(tokenId);
    }


    /// Admin methods

    /// @notice Sets USDT-denominated prices per lootbox type.
    /// @dev Only callable by DEFAULT_ADMIN_ROLE. Emits `PriceSet` for each typeId.
    /// @param prices Array of prices in USDT (raw units), indexed by typeId.
    function setPrices(uint256[] memory prices) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setPrices(prices);
    }

    /// @notice Sets the store's burn share percentage (scaled by PERCENT_PRECISION).
    /// @dev Must be &lt;= 100% (PERCENT_PRECISION). The remainder after referrals and vault share is paid to the team.
    /// @param sharePercents New burn share in PERCENT_PRECISION units.
    function setBurnShare(uint256 sharePercents) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(sharePercents <= PERCENT_PRECISION, "Share exceeds 100%");
        burnShare = sharePercents;
        emit BurnShareSet(sharePercents);
    }

    /// @notice Updates the burn payout account.
    /// @dev Only callable by DEFAULT_ADMIN_ROLE.
    /// @param accountAddress Address to receive the burn part of the revenue.
    function setBurnAccount(address accountAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        burnAccount = accountAddress;
        emit BurnAccountSet(accountAddress);
    }

    /// @notice Updates the team payout account.
    /// @dev Only callable by DEFAULT_ADMIN_ROLE.
    /// @param accountAddress Address to receive the team part of the revenue.
    function setTeamAccount(address accountAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        teamAccount = accountAddress;
        emit TeamAccountSet(accountAddress);
    }

    function setTokenDiscount(address tokenAddress, uint256 discountPercents) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _discount[tokenAddress] = discountPercents;
        emit TokenDiscountSet(tokenAddress, discountPercents);
    }


    /// Internal methods

    /// @notice Reverts if a non-native payment token is not allowed by the vault.
    /// @dev Native payments use `address(0)`. ERC20 tokens must be enabled in the vault.
    /// @param tokenAddress Address of the payment token (use address(0) for BNB).
    function _requireTokenAvailable(address tokenAddress) internal view {
        require(_tokens.contains(tokenAddress), "Token is not allowed");
    }

    function _addDrop(uint256 typeId, UpgradeChance memory drop) internal returns (uint256 newDropId) {
        _typeDrop[typeId].push(drop);
        newDropId = _typeDrop[typeId].length;
        emit TypeDropAdded(typeId, newDropId, drop);
        return newDropId;
    }

    function _pseudoRandom(uint256 mod) internal returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, ++_randomCounter)))
            % mod;
    }

    function _rollDrop(uint256 typeId) internal returns (uint256) {
        uint rand = _pseudoRandom(PERCENT_PRECISION);
        uint chance;
        if (_typeDrop[typeId].length > 1) {
            for (uint256 rarity = _typeDrop[typeId].length - 1; rarity > 0; rarity--) {
                chance += _typeDrop[typeId][rarity].chance;
                if (rand <= chance) {
                    return rarity;
                }
            }
        }
        return 0;
    }

    function _upgrade(uint256 tokenId) internal returns (uint256 nftItemId) {
        address holder = _msgSender();
        key.burn(holder, tokenId);

        uint256 typeId = key.tokenTypeId(tokenId);
        uint256 rarity = _rollDrop(typeId);
        UpgradeChance storage drop = _typeDrop[typeId][rarity];

        if (drop.typeId > 0) {
            nftItemId = key.mint(holder, drop.typeId);
            emit KeyUpgraded(holder, typeId, tokenId, drop.typeId, nftItemId);
        } else {
            emit KeyBurned(holder, typeId, tokenId);
        }
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
        if (percentsLeft > burnShare) {
            uint256 teamShareAmount = (percentsLeft - burnShare) * amount / PERCENT_PRECISION;
            _send(tokenAddress, holder, teamAccount, teamShareAmount);
            emit TeamRewardSent(holder, teamAccount, tokenAddress, teamShareAmount);
            percentsLeft = burnShare;
        }

        /// Send to the vault
        uint256 burnShareAmount = percentsLeft * amount / PERCENT_PRECISION;
        _send(tokenAddress, holder, address(burnAccount), burnShareAmount);
        emit BurnAccountRefilled(holder, tokenAddress, burnShareAmount);
    }

    function _pay(uint256 tokenId, address tokenAddress) internal returns (uint256 price) {
        uint256 typeId = key.tokenTypeId(tokenId);
        address holder = _msgSender();
        require(holder == key.ownerOf(tokenId), "Wrong token owner");
        require(block.timestamp < vault.unlockDate(), "Sale is not available");
        require(typeId < key.getTypes().length && _prices[typeId] > 0, "Upgrade of this NFT type is not available");
        _requireTokenAvailable(tokenAddress);
        
        /// Get initial data
        ReferralPercents[] memory refs = _referral.getReferralPercents(holder);
        price = tokenAddress == address(0)
            ? _quoteBNBForUSDT(_prices[typeId])
            : _quoteTokenForUSDT(tokenAddress, _prices[typeId]);
        price -= price * _discount[tokenAddress] / PERCENT_PRECISION;

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
                revert NotEnoughTokens(price, allowance);
            }
            /// Distribute payment
            _distributePayment(holder, refs, tokenAddress, price);
        }
    }


}