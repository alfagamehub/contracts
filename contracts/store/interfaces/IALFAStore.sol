// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IALFAVault, TokenInfo} from "../../vault/interfaces/IALFAVault.sol";

struct LootBoxPrice {
    uint256 typeId;
    address tokenAddress;
    uint256 amount;
}

error NotEnoughTokens(uint256 required, uint256 received);
error NotEnoughAllowance(uint256 required, uint256 received);

interface IALFAStore {

    event PriceSet(uint256 typeId, uint256 price);
    event LootBoxSold(address indexed holder, uint256 indexed typeId, uint256[] tokenId, address tokenAddress, uint256 tokenAmount);
    event ReferralRewardSent(address indexed holder, address indexed receiver, address indexed child, address tokenAddress, uint256 tokenAmount);
    event TeamRewardSent(address indexed holder, address indexed teamAccount, address tokenAddress, uint256 tokenAmount);
    event VaultRefilled(address indexed holder, address tokenAddress, uint256 tokenAmount);
    event TeamAccountSet(address accountAddress);
    event VaultShareSet(uint256 sharePercents);

    /// @notice Returns the configured vault share (scaled by PERCENT_PRECISION).
    function vaultShare() external view returns (uint256);

    /// @notice Returns the current team payout account.
    function teamAccount() external view returns (address);

    // -------- Read methods --------

    /// @notice Returns a matrix of lootbox prices for all token types in all accepted tokens.
    /// @dev Rows correspond to lootbox typeId, columns correspond to tokens returned by `vault.getVaultTokens()`.
    ///      Each cell is the quoted amount of a token needed to pay the USDT-denominated price for that lootbox type.
    /// @return lootBoxPrice A 2D array [typeId][tokenIndex] with token address and amount.
    function getPrices() external view returns (LootBoxPrice[][] memory lootBoxPrice);

    // -------- Write methods --------

    /// @notice Buys lootboxes with an ERC20 token and optional referral parents chain.
    /// @param typeId Lootbox type identifier.
    /// @param tokenAddress Payment token address (must be allowed by the vault).
    /// @param boxAmount Number of lootboxes to buy (must be > 0).
    /// @param parents Referral chain (closest parent first). May be empty.
    /// @return tokenId Array of minted lootbox token IDs.
    function buy(uint256 typeId, address tokenAddress, uint256 boxAmount, address[] calldata parents)
        external
        returns (uint256[] memory tokenId);

    /// @notice Buys lootboxes with native BNB and optional referral parents chain.
    /// @param typeId Lootbox type identifier.
    /// @param boxAmount Number of lootboxes to buy (must be > 0).
    /// @param parents Referral chain (closest parent first). May be empty.
    /// @return tokenId Array of minted lootbox token IDs.
    function buy(uint256 typeId, uint256 boxAmount, address[] calldata parents)
        external
        payable
        returns (uint256[] memory tokenId);

    /// @notice Sets USDT-denominated prices per lootbox type.
    /// @param prices Array of prices in USDT (raw units), indexed by typeId.
    function setPrices(uint256[] calldata prices) external;

    /// @notice Sets the store's vault share percentage (scaled by PERCENT_PRECISION).
    /// @param sharePercents New vault share in PERCENT_PRECISION units (must be &lt;= 100%).
    function setVaultShare(uint256 sharePercents) external;

    /// @notice Updates the team payout account.
    /// @param accountAddress Address to receive the team part of the revenue.
    function setTeamAccount(address accountAddress) external;

}