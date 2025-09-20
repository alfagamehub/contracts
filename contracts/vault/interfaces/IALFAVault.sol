// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct TokenInfo {
    address tokenAddress;
    uint256 amount;
}

interface IALFAVault {

    event TokenAdded(address indexed tokenAddress);
    event TokenRemoved(address indexed tokenAddress);
    event MasterKeySet(uint256 keyIndex);
    event UnlockDateSet(uint256 unlockDateSeconds);
    event RedeemUntilDateSet(uint256 redeemUntilDateSeconds);
    event RewardRedeemed(address indexed holder, address indexed tokenAddres, uint256 amount, uint256 keyTokenId);
    event RewardWithdrawn(address indexed tokenAddress, uint256 amount, address receiver);

    /// @notice Returns the configured unlock date timestamp.
    function unlockDate() external view returns (uint256);

    /// @notice Returns the final redeem-until date timestamp.
    function redeemUntilDate() external view returns (uint256);

    /// @notice Returns information about all ERC20 tokens held in the vault.
    function getVaultTokens() external view returns (TokenInfo[] memory);

    /// @notice Returns the holder's share of the vault in percent scaled by PERCENT_PRECISION.
    /// @param holder The address of the holder to query.
    function getHolderShare(address holder) external view returns (uint256);

    /// @notice Returns total number of master keys issued.
    function getKeysTotalAmount() external view returns (uint256);

    /// @notice Returns a summary of the vault state.
    /// @return tokens Array of TokenInfo.
    /// @return keysTotalAmount Total master keys.
    /// @return unlockDateSeconds Unlock date timestamp.
    /// @return redeemUntilDateSeconds Redeem-until date timestamp.
    function getInfo() external view returns (
        TokenInfo[] memory tokens,
        uint256 keysTotalAmount,
        uint256 unlockDateSeconds,
        uint256 redeemUntilDateSeconds
    );

    /// @notice Checks whether a token is currently allowed in the vault.
    /// @param tokenAddress ERC20 token address to check.
    function getTokenAvailable(address tokenAddress) external view returns (bool);

    /// @notice Redeems rewards using a valid master key NFT.
    /// @param tokenId The NFT key tokenId used to redeem.
    function redeem(uint256 tokenId) external;

    /// @notice Adds an ERC20 token to the allowed tokens list.
    /// @param tokenAddress ERC20 token address to add.
    function addToken(address tokenAddress) external;

    /// @notice Removes an ERC20 token from the allowed tokens list.
    /// @param tokenAddress ERC20 token address to remove.
    function removeToken(address tokenAddress) external;

    /// @notice Sets the master key type index used for redemption eligibility.
    /// @param masterKeyIndex New master key type id.
    function setMasterKey(uint256 masterKeyIndex) external;

    /// @notice Sets the unlock date timestamp.
    /// @param unlockDateSeconds New unlock date.
    function setUnlockDate(uint256 unlockDateSeconds) external;

    /// @notice Sets the redeem-until date timestamp.
    /// @param redeemUntilDateSeconds New redeem-until date.
    function setRedeemUntilDate(uint256 redeemUntilDateSeconds) external;

    /// @notice Withdraws a specific token amount (after redeem period ends).
    /// @param tokenAddress ERC20 token to withdraw.
    /// @param amount Amount to withdraw.
    function withdraw(address tokenAddress, uint256 amount) external;

    /// @notice Withdraws entire balance of a specific token (after redeem period ends).
    /// @param tokenAddress ERC20 token to withdraw entirely.
    function withdraw(address tokenAddress) external;

    /// @notice Withdraws entire balance of all tokens (after redeem period ends).
    function withdraw() external;
}