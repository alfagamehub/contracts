// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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

interface IALFAForge {

    event TypeDropAdded(uint256 indexed typeId, uint256 dropIndex, UpgradeChance drop);
    event TypeDropCleared(uint256 indexed typeId);

    event KeyUpgraded(address indexed holder, uint256 typeId, uint256 tokenId, uint256 newTypeId, uint256 newTokenId);
    event KeyBurned(address indexed holder, uint256 typeId, uint256 tokenId);

    event PriceSet(uint256 typeId, uint256 price);
    event ReferralRewardSent(address indexed holder, address indexed receiver, address indexed child, address tokenAddress, uint256 tokenAmount);
    event BurnAccountRefilled(address indexed holder, address tokenAddress, uint256 tokenAmount);
    event TeamRewardSent(address indexed holder, address indexed teamAccount, address tokenAddress, uint256 tokenAmount);
    event TeamAccountSet(address accountAddress);
    event BurnAccountSet(address accountAddress);
    event BurnShareSet(uint256 sharePercents);
    event TokenDiscountSet(address tokenAddress, uint256 discountPercents);

}