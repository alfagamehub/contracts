// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

error NotEnoughTokens(uint256 required, uint256 received);

interface IALFAStore {

    event PriceSet(uint256 typeId, uint256 price);
    event LootBoxSold(address indexed holder, uint256 indexed typeId, uint256[] tokenId, address tokenAddress, uint256 tokenAmount);
    event ReferralRewardSent(address indexed holder, address indexed receiver, address indexed child, address tokenAddress, uint256 tokenAmount);
    event TeamRewardSent(address indexed holder, address indexed teamAccount, address tokenAddress, uint256 tokenAmount);
    event VaultRefilled(address indexed holder, address tokenAddress, uint256 tokenAmount);
    event TeamAccountSet(address accountAddress);
    event VaultShareSet(uint256 sharePercents);

}