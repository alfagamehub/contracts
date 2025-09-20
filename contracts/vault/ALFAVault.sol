// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl, IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IALFAVault, TokenInfo} from "./interfaces/IALFAVault.sol";
import {IALFAKey} from "../NFT/Key/IALFAKey.sol";
import {PERCENT_PRECISION} from "../const.sol";

contract ALFAVault is AccessControl, IALFAVault {

    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _tokens;
    IALFAKey private _keys;
    uint256 private _masterKeyTypeId;
    uint256 public unlockDate;
    uint256 public redeemUntilDate;

    /// @notice Deploys the ALFAVault contract with initial configuration.
    /// @dev Grants admin role to deployer, sets keys contract, tokens, unlock, and redeem dates.
    /// @param alfaKeyAddress The address of the ALFAKey NFT contract.
    /// @param tokens The list of ERC20 token addresses to be managed by the vault.
    /// @param unlockDateSeconds The timestamp after which rewards can be redeemed.
    /// @param redeemUntilDateSeconds The timestamp until which rewards can be redeemed.
    constructor(
        address alfaKeyAddress,
        address[] memory tokens,
        uint256 unlockDateSeconds,
        uint256 redeemUntilDateSeconds
        ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _keys = IALFAKey(alfaKeyAddress);
        _masterKeyTypeId = 4;
        for (uint256 i; i < tokens.length; i++) {
            _addToken(tokens[i]);
        }

        unlockDate = unlockDateSeconds;
        emit UnlockDateSet(unlockDateSeconds);

        redeemUntilDate = redeemUntilDateSeconds;
        emit RedeemUntilDateSet(redeemUntilDateSeconds);
    }

    receive() external payable {}


    /// Write methods

    /// @notice Redeems rewards for a valid master key NFT.
    /// @dev Caller must own the key, key type must match the master key, and redemption must be within allowed period.
    /// @param tokenId The ID of the NFT key used for redemption.
    function redeem(uint256 tokenId) public {
        require(_keys.tokenTypeId(tokenId) == _masterKeyTypeId, "Selected key is not valid");
        require(block.timestamp >= unlockDate, "Redeem is not available yet");
        require(block.timestamp <= redeemUntilDate, "Redeem is not available anymore");

        address holder = _msgSender();
        uint256 total = _getKeysTotalAmount();
        for (uint256 i; i < _tokens.length(); i++) {
            uint256 amount = _getBalance(_tokens.at(i)) / total;
            if (_tokens.at(i) == address(0)) {
                (bool sent,) = holder.call{value: amount}("");
                require(sent, "Failed to send BNB");
            } else {
                require(IERC20(_tokens.at(i)).transfer(holder, amount), "Can't transfer reward");
            }
            emit RewardRedeemed(holder, _tokens.at(i), amount, tokenId);
        }
        _keys.burn(holder, tokenId);
    }


    /// Read methods

    /// @notice Returns information about all tokens held in the vault.
    /// @dev Each TokenInfo contains token address and current vault balance.
    /// @return Array of TokenInfo for each token in the vault.
    function getVaultTokens() public view returns (TokenInfo[] memory) {
        TokenInfo[] memory result = new TokenInfo[](_tokens.length());
        for (uint256 i; i < _tokens.length(); i++) {
            result[i].tokenAddress = _tokens.at(i);
            result[i].amount = _getBalance(result[i].tokenAddress);
        }
        return result;
    }

    /// @notice Returns the share of the vault a holder owns, as a percentage.
    /// @dev Share is calculated as holder's master keys over total, scaled by PERCENT_PRECISION.
    /// @param holder The address of the holder to query.
    /// @return The percent share (scaled by PERCENT_PRECISION) owned by the holder.
    function getHolderShare(address holder) public view returns (uint256) {
        uint256 total = _getKeysTotalAmount();
        return total > 0
            ? _getKeysHolderAmount(holder) * PERCENT_PRECISION / total
            : 0;
    }

    /// @notice Returns the total amount of master keys issued.
    /// @dev Queries the keys contract for the amount of master key type.
    /// @return The total number of master keys.
    function getKeysTotalAmount() public view returns (uint256) {
        return _getKeysTotalAmount();
    }

    /// @notice Returns vault summary information.
    /// @dev Includes tokens, total master keys, unlock date, and redeem until date.
    /// @return tokens Array of TokenInfo for each token.
    /// @return keysTotalAmount The total number of master keys.
    /// @return unlockDateSeconds The unlock date timestamp.
    /// @return redeemUntilDateSeconds The redeem until date timestamp.
    function getInfo() public view returns (
        TokenInfo[] memory tokens,
        uint256 keysTotalAmount,
        uint256 unlockDateSeconds,
        uint256 redeemUntilDateSeconds
    ) {
        return (getVaultTokens(), _getKeysTotalAmount(), unlockDate, redeemUntilDate);
    }

    /// @notice Checks if a given token address is part of the allowed vault tokens.
    /// @dev Supports both ERC20 token addresses and the native token placeholder (address(0)) if added.
    /// @param tokenAddress The address of the token to check.
    /// @return True if the token is currently allowed in the vault, false otherwise.
    function getTokenAvailable(address tokenAddress) public view returns (bool) {
        return _tokens.contains(tokenAddress);
    }


    /// Admin methods

    /// @notice Adds a new ERC20 token to the vault.
    /// @dev Only callable by admin. The token must not already be allowed.
    /// @param tokenAddress The address of the ERC20 token to add.
    function addToken(address tokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _addToken(tokenAddress);
    }

    /// @notice Removes an ERC20 token from the vault.
    /// @dev Only callable by admin. The token must be currently allowed.
    /// @param tokenAddress The address of the ERC20 token to remove.
    function removeToken(address tokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeToken(tokenAddress);
    }

    /// @notice Sets the master key type ID for redemption eligibility.
    /// @dev Only callable by admin.
    /// @param masterKeyIndex The new master key type ID.
    function setMasterKey(uint256 masterKeyIndex) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _masterKeyTypeId = masterKeyIndex;
        emit MasterKeySet(masterKeyIndex);
    }

    /// @notice Sets the unlock date after which rewards can be redeemed.
    /// @dev Only callable by admin.
    /// @param unlockDateSeconds The new unlock date as a timestamp.
    function setUnlockDate(uint256 unlockDateSeconds) public onlyRole(DEFAULT_ADMIN_ROLE) {
        unlockDate = unlockDateSeconds;
        emit UnlockDateSet(unlockDateSeconds);
    }

    /// @notice Sets the final date until which rewards can be redeemed.
    /// @dev Only callable by admin.
    /// @param redeemUntilDateSeconds The new redeem until date as a timestamp.
    function setRedeemUntilDate(uint256 redeemUntilDateSeconds) public onlyRole(DEFAULT_ADMIN_ROLE) {
        redeemUntilDate = redeemUntilDateSeconds;
        emit RedeemUntilDateSet(redeemUntilDateSeconds);
    }

    /// @notice Withdraws a specific amount of a token after redemption period ends.
    /// @dev Only callable by admin. Withdrawals only allowed after redeem period.
    /// @param tokenAddress The address of the ERC20 token to withdraw.
    /// @param amount The amount of tokens to withdraw.
    function withdraw(address tokenAddress, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _withdraw(tokenAddress, amount);
    }

    /// @notice Withdraws the entire balance of a token after redemption period ends.
    /// @dev Only callable by admin. Withdrawals only allowed after redeem period.
    /// @param tokenAddress The address of the ERC20 token to withdraw.
    function withdraw(address tokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _withdraw(tokenAddress, _getBalance(tokenAddress));
    }

    /// @notice Withdraws the entire balance of all tokens after redemption period ends.
    /// @dev Only callable by admin. Withdrawals only allowed after redeem period.
    function withdraw() public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i; i < _tokens.length(); i++) {
            _withdraw(_tokens.at(i), _getBalance(_tokens.at(i)));
        }
    }


    /// Internal methods

    function _addToken(address tokenAddress) internal returns (uint256) {
        require(!_tokens.contains(tokenAddress), "Token is already allowed");
        _tokens.add(tokenAddress);
        emit TokenAdded(tokenAddress);
        return _tokens.length() - 1;
    }

    function _removeToken(address tokenAddress) internal {
        _requireTokenExists(tokenAddress);
        _tokens.remove(tokenAddress);
        emit TokenRemoved(tokenAddress);
    }

    function _requireTokenExists(address tokenAddress) internal view {
        require(_tokens.contains(tokenAddress), "Token is not allowed");
    }
    
    function _getBalance(address tokenAddress) internal view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function _getKeysTotalAmount() internal view returns (uint256) {
        return _keys.getTypeAmount(_masterKeyTypeId);
    }

    function _getKeysHolderAmount(address holder) internal view returns (uint256) {
        return _keys.getTypeHolderAmount(holder, _masterKeyTypeId);
    }

    function _withdraw(address tokenAddress, uint256 amount) internal {
        if (_tokens.contains(tokenAddress)) {
            require(block.timestamp > redeemUntilDate, "Holders still can redeem their reward");
        }
        if (tokenAddress == address(0)) {
            (bool sent,) = _msgSender().call{value: amount}("");
            require(sent, "Failed to send BNB");
        } else {
            require(IERC20(tokenAddress).transfer(_msgSender(), amount), "Can't transfer reward");
        }
        emit RewardWithdrawn(tokenAddress, amount, _msgSender());
    }

}