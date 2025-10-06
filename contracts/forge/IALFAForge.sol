// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IALFAKey} from "../NFT/Key/IALFAKey.sol";
import {IALFAVault} from "../vault/interfaces/IALFAVault.sol";

struct UpgradeChance {
    uint256 typeId;
    uint256 chance;
}

struct UpgradePrice {
    uint256 typeId;
    address tokenAddress;
    uint256 amount;
}

error NotEnoughTokens(uint256 required, uint256 received);
error NotEnoughAllowance(uint256 required, uint256 received);

interface IALFAForge {

    event TypeDropAdded(uint256 indexed typeId, uint256 dropIndex, UpgradeChance drop);
    event TypeDropCleared(uint256 indexed typeId);

    event KeyUpgraded(address indexed holder, uint256 typeId, uint256[] tokenId, uint256 newTypeId, uint256 newTokenId);
    event KeyBurned(address indexed holder, uint256 typeId, uint256[] tokenId);

    event PriceSet(uint256 typeId, uint256 price);
    event ReferralRewardSent(address indexed holder, address indexed receiver, address indexed child, address tokenAddress, uint256 tokenAmount);
    event BurnAccountRefilled(address indexed holder, address tokenAddress, uint256 tokenAmount);
    event TeamRewardSent(address indexed holder, address indexed teamAccount, address tokenAddress, uint256 tokenAmount);
    event TeamAccountSet(address accountAddress);
    event BurnAccountSet(address accountAddress);
    event BurnShareSet(uint256 sharePercents);
    event TokenDiscountSet(address tokenAddress, uint256 discountPercents);
    event TokenAdded(address indexed tokenAddress);
    event TokenRemoved(address indexed tokenAddress);

    // -------- View getters (derived from public state) --------

    /// @notice Returns the ALFA Key contract used by the forge.
    function key() external view returns (IALFAKey);

    /// @notice Returns the vault contract used for schedule checks and to receive refunds on failures.
    function vault() external view returns (IALFAVault);

    /// @notice Returns the current team payout account.
    function teamAccount() external view returns (address);

    /// @notice Returns the current burn payout account.
    function burnAccount() external view returns (address);

    /// @notice Returns the configured burn share percentage (scaled by PERCENT_PRECISION).
    function burnShare() external view returns (uint256);

    /// @notice Checks whether a payment token is currently allowed for upgrades.
    /// @param tokenAddress Address of the payment token (use address(0) for BNB).
    function getTokenAvailable(address tokenAddress) external view returns (bool);

    // -------- Read methods --------

    /// @notice Returns a matrix of upgrade prices for each key type and each accepted payment token.
    /// @dev Rows correspond to target upgrade typeId (1..N-1); columns to accepted payment tokens.
    /// @return upgradePrice A 2D array [typeIdIndex][tokenIndex] with token address, typeId and amount.
    function getPrices() external view returns (UpgradePrice[][] memory upgradePrice);

    // -------- Write methods --------

    /// @notice Upgrades a key by paying with an ERC20 token.
    /// @param tokenId ID of the key to upgrade (must be owned by caller).
    /// @param tokenAddress ERC20 token used for payment (must be in the allowlist).
    /// @return newItemId ID of the newly minted key if upgrade hits a non-zero type; otherwise 0.
    function upgrade(uint256[] memory tokenId, address tokenAddress) external returns (uint256 newItemId);

    /// @notice Upgrades a key by paying with native BNB.
    /// @param tokenId ID of the key to upgrade (must be owned by caller).
    /// @return newItemId ID of the newly minted key if upgrade hits a non-zero type; otherwise 0.
    function upgrade(uint256[] memory tokenId) external payable returns (uint256 newItemId);

    /// @notice Sets USDT-denominated upgrade prices per key type.
    /// @param prices Array of prices in USDT (raw units), indexed by typeId.
    function setPrices(uint256[] calldata prices) external;

    /// @notice Sets the burn share percentage (scaled by PERCENT_PRECISION).
    /// @param sharePercents New burn share in PERCENT_PRECISION units.
    function setBurnShare(uint256 sharePercents) external;

    /// @notice Updates the burn payout account.
    /// @param accountAddress Address to receive the burn part of the revenue.
    function setBurnAccount(address accountAddress) external;

    /// @notice Updates the team payout account.
    /// @param accountAddress Address to receive the team part of the revenue.
    function setTeamAccount(address accountAddress) external;

    /// @notice Sets a discount percentage for a specific payment token.
    /// @param tokenAddress Payment token to discount (use address(0) for native BNB).
    /// @param discountPercents Discount in PERCENT_PRECISION units.
    function setTokenDiscount(address tokenAddress, uint256 discountPercents) external;

    /// @notice Adds a payment token to the allowlist.
    /// @param tokenAddress Address of the token to add (use address(0) for native BNB).
    /// @return newIndex Index of the token inside the allowlist.
    function addToken(address tokenAddress) external returns (uint256 newIndex);

    /// @notice Removes a payment token from the allowlist.
    /// @param tokenAddress Address of the token to remove (use address(0) for native BNB).
    function removeToken(address tokenAddress) external;
}
