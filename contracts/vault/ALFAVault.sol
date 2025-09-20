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


    /// Write methods

    function redeem(uint256 tokenId) public {
        require(_keys.tokenTypeId(tokenId) == _masterKeyTypeId, "Selected key is not valid");
        require(block.timestamp >= unlockDate, "Redeem is not available yet");
        require(block.timestamp <= redeemUntilDate, "Redeem is not available anymore");

        address holder = _msgSender();
        uint256 total = _getKeysTotalAmount();
        for (uint256 i; i < _tokens.length(); i++) {
            uint256 amount = _getBalance(_tokens.at(i)) / total;
            require(IERC20(_tokens.at(i)).transfer(holder, amount), "Can't transfer reward");
            emit RewardRedeemed(holder, _tokens.at(i), amount, tokenId);
        }
        _keys.burn(holder, tokenId);
    }


    /// Read methods

    function getVaultTokens() public view returns (TokenInfo[] memory) {
        TokenInfo[] memory result = new TokenInfo[](_tokens.length());
        for (uint256 i; i < _tokens.length(); i++) {
            result[i].tokenAddress = _tokens.at(i);
            result[i].amount = _getBalance(result[i].tokenAddress);
        }
        return result;
    }

    function getHolderShare(address holder) public view returns (uint256) {
        uint256 total = _getKeysTotalAmount();
        return total > 0
            ? _getKeysHolderAmount(holder) * PERCENT_PRECISION / total
            : 0;
    }

    function getKeysTotalAmount() public view returns (uint256) {
        return _getKeysTotalAmount();
    }

    function getInfo() public view returns (
        TokenInfo[] memory,
        uint256 keysTotalAmount,
        uint256 unlockDateSeconds,
        uint256 redeemUntilDateSeconds
    ) {
        return (getVaultTokens(), _getKeysTotalAmount(), unlockDate, redeemUntilDate);
    }


    /// Admin methods

    function addToken(address tokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _addToken(tokenAddress);
    }

    function removeToken(address tokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeToken(tokenAddress);
    }

    function setMasterKey(uint256 masterKeyIndex) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _masterKeyTypeId = masterKeyIndex;
        emit MasterKeySet(masterKeyIndex);
    }

    function setUnlockDate(uint256 unlockDateSeconds) public onlyRole(DEFAULT_ADMIN_ROLE) {
        unlockDate = unlockDateSeconds;
        emit UnlockDateSet(unlockDateSeconds);
    }

    function setRedeemUntilDate(uint256 redeemUntilDateSeconds) public onlyRole(DEFAULT_ADMIN_ROLE) {
        redeemUntilDate = redeemUntilDateSeconds;
        emit RedeemUntilDateSet(redeemUntilDateSeconds);
    }

    function withdraw(address tokenAddress, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _withdraw(tokenAddress, amount);
    }

    function withdraw(address tokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _withdraw(tokenAddress, _getBalance(tokenAddress));
    }

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
        require(block.timestamp > redeemUntilDate, "Holders still can redeem their reward");
        require(IERC20(tokenAddress).transfer(_msgSender(), amount), "Can't transfer reward");
        emit RewardWithdrawn(tokenAddress, amount, _msgSender());
    }

}