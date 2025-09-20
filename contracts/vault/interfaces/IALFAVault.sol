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

}