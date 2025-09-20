// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

struct DropChance {
    address tokenAddress;
    uint256 typeId;
    uint256 chance;
}

struct TokenType {
    uint256 typeId;
    uint256 count;
    string typeName;
    string typeURI;
    DropChance[] drop;
}

struct HolderToken {
    uint256 tokenId;
    uint256 typeId;
}

interface IALFALootbox is IERC721, IERC721Metadata {

    event TypeAdded(uint256 indexed typeId, string typeName, string typeURI);
    event TypeRemoved(uint256 indexed typeId);
    event TypeUpdated(uint256 indexed typeId, string typeName, string typeURI);
    event TypeDropAdded(uint256 indexed typeId, uint256 dropIndex, DropChance drop);
    event TypeDropCleared(uint256 indexed typeId);

    event TokenMinted(uint256 indexed typeId, address indexed holder, uint256 tokenId, uint256 totalCount);
    event TokenBurned(uint256 indexed typeId, address indexed holder, uint256 tokenId, uint256 totalCount);
    event DropRolled(address indexed holder, uint256 indexed typeId, uint256 indexed tokenId, address dropAddress, uint256 dropTypeId, uint256 dropId);

    function getTypes() external view returns (TokenType[] memory);
    function getTokens(address holder, uint256 offset, uint256 limit) external view returns (HolderToken[] memory, uint256 count);

    function getTypeAmount(uint256 typeId) external view returns (uint256);
    function getTypeHolderAmount(address holder, uint256 typeId) external view returns (uint256);
    function getHolderAmounts(address holder) external view returns (uint256[] memory);

    function tokenType(uint256 tokenId) external view returns (TokenType memory data);
    function tokenTypeId(uint256 tokenId) external view returns (uint256);

    function mint(address receiver, uint256 typeId) external returns (uint256 newTokenId);
    function burn(address holder, uint256 tokenId) external;

    function addType(string calldata typeName, string calldata typeURI) external returns (uint256 newTypeId);
    function removeType(uint256 typeId) external;
    function updateType(uint256 typeId, string calldata typeName, string calldata typeURI) external;

}