// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721, IERC721, IERC165, IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl, IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IALFALootbox, TokenType, HolderToken, DropChance} from "./IALFALootbox.sol";
import {PERCENT_PRECISION} from "../../const.sol";

/// @title ALFA Lootbox NFT
/// @notice Typed NFT
contract ALFALootbox is ERC721, AccessControl, IALFALootbox {

    using EnumerableSet for EnumerableSet.UintSet;

    bytes32 public constant EDITOR_ROLE = keccak256("EDITOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    
    uint256 internal _typesIndex = 1;
    uint256 internal _tokenIndex = 1;

    EnumerableSet.UintSet internal _types;
    mapping(uint256 typeId => string typeName) internal _typeName;
    mapping(uint256 typeId => string typeURI) internal _typeURI;
    mapping(uint256 typeId => DropChance[] drop) internal _typeDrop;
    mapping(uint256 typeId => uint256 count) internal _typeCount;

    mapping(uint256 tokenId => uint256 typeId) internal _tokenType;
    mapping(address holder => EnumerableSet.UintSet tokens) internal _holderTokens;
    mapping(address holder => mapping (uint256 typeId => uint256 amount)) internal _holderAmounts;

    uint256 private _randomCounter;

    /// @notice Initializes the ALFA Lootbox contract with predefined types and drop chances
    /// @param keysAddress Address of the keys token contract used for drops
    constructor(address keysAddress) ERC721("ALFA Lootbox", "ALBOX") {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(EDITOR_ROLE, _msgSender());

        _addType("Common", "https://api.alfagame.xyz/static/boxes/green.mp4");
        _addDrop(1, DropChance(keysAddress, 1, 970000));
        _addDrop(1, DropChance(keysAddress, 2,  24000));
        _addDrop(1, DropChance(keysAddress, 3,   5100));
        _addDrop(1, DropChance(keysAddress, 4,    800));
        _addDrop(1, DropChance(keysAddress, 5,    100));

        _addType("Rare", "https://api.alfagame.xyz/static/boxes/blue.mp4");
        _addDrop(2, DropChance(keysAddress, 1, 230000));
        _addDrop(2, DropChance(keysAddress, 2, 740000));
        _addDrop(2, DropChance(keysAddress, 3,  25500));
        _addDrop(2, DropChance(keysAddress, 4,   4000));
        _addDrop(2, DropChance(keysAddress, 5,    500));

        _addType("Epic", "https://api.alfagame.xyz/static/boxes/yellow.mp4");
        _addDrop(3, DropChance(keysAddress, 1,  10000));
        _addDrop(3, DropChance(keysAddress, 2, 250000));
        _addDrop(3, DropChance(keysAddress, 3, 716500));
        _addDrop(3, DropChance(keysAddress, 4,  20000));
        _addDrop(3, DropChance(keysAddress, 5,   3500));

        _addType("Legendary", "https://api.alfagame.xyz/static/boxes/red.mp4");
        _addDrop(4, DropChance(keysAddress, 1,   1000));
        _addDrop(4, DropChance(keysAddress, 2,  10000));
        _addDrop(4, DropChance(keysAddress, 3, 270000));
        _addDrop(4, DropChance(keysAddress, 4, 699000));
        _addDrop(4, DropChance(keysAddress, 5,  20000));

        _addType("Mystic", "https://api.alfagame.xyz/static/boxes/purple.mp4");
        _addDrop(5, DropChance(keysAddress, 1,      0));
        _addDrop(5, DropChance(keysAddress, 2,      0));
        _addDrop(5, DropChance(keysAddress, 3,      0));
        _addDrop(5, DropChance(keysAddress, 4,  50000));
        _addDrop(5, DropChance(keysAddress, 5, 950000));
    }


    /// Read methods

    /// @notice Returns the list of all token types with their metadata and drop chances
    /// @return Array of TokenType structs representing all available types
    function getTypes() public view returns (TokenType[] memory) {
        uint256 length = _types.length();
        TokenType[] memory list = new TokenType[](length);
        for (uint256 i; i < length; i++) {
            list[i].typeId = _types.at(i);
            list[i].count = _typeCount[list[i].typeId];
            list[i].typeName = _typeName[list[i].typeId];
            list[i].typeURI = _typeURI[list[i].typeId];
            list[i].drop = _typeDrop[list[i].typeId];
        }
        return list;
    }

    /// @notice Returns a paginated list of tokens owned by a holder
    /// @param holder Address of the token holder
    /// @param offset Index offset to start from
    /// @param limit Maximum number of tokens to return
    /// @return Array of HolderToken structs representing the tokens
    /// @return count Total number of tokens owned by the holder
    function getTokens(address holder, uint256 offset, uint256 limit) public view returns (HolderToken[] memory, uint256 count) {
        count = _holderTokens[holder].length();
        if (offset >= count || limit == 0) return (new HolderToken[](0), count);
        uint256 length = count - offset;
        if (limit < length) length = limit;
        HolderToken[] memory data = new HolderToken[](length);
        for (uint256 i; i < length; i++) {
            data[i].tokenId = _holderTokens[holder].at(i);
            data[i].typeId = _tokenType[data[i].tokenId];
        }
        return (data, count);
    }

    /// @notice Returns the metadata URI of a given token
    /// @param tokenId Identifier of the token
    /// @return URI string of the token's metadata
    function tokenURI(uint256 tokenId) public view override(ERC721, IERC721Metadata) returns (string memory) {
        _requireOwned(tokenId);
        return _typeURI[tokenTypeId(tokenId)];
    }

    /// @notice Returns the TokenType struct for a given token
    /// @param tokenId Identifier of the token
    /// @return data TokenType struct containing type metadata and drop chances
    function tokenType(uint256 tokenId) public view returns (TokenType memory data) {
        uint256 typeId = tokenTypeId(tokenId);

        data.typeId = typeId;
        data.count = _typeCount[typeId];
        data.typeName = _typeName[typeId];
        data.typeURI = _typeURI[typeId];
    }

    /// @notice Returns the type identifier of a given token
    /// @param tokenId Identifier of the token
    /// @return Type identifier of the token
    function tokenTypeId(uint256 tokenId) public view returns (uint256) {
        _requireOwned(tokenId);
        return _tokenType[tokenId];
    }

    /// @notice Returns the total number of tokens of a specific type
    /// @param typeId Identifier of the token type
    /// @return Number of tokens of the specified type
    function getTypeAmount(uint256 typeId) public view returns (uint256) {
        return _typeCount[typeId];
    }

    /// @notice Returns the number of tokens of a specific type owned by a holder
    /// @param holder Address of the token holder
    /// @param typeId Identifier of the token type
    /// @return Number of tokens of the specified type owned by the holder
    function getTypeHolderAmount(address holder, uint256 typeId) public view returns (uint256) {
        return _holderAmounts[holder][typeId];
    }

    /// @notice Returns an array of token counts owned by a holder, separated by token type
    /// @param holder Address of the token holder
    /// @return Array of token counts indexed by token type
    function getHolderAmounts(address holder) public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](_types.length());
        for (uint256 i; i < _types.length(); i++) {
            amounts[i] = _holderAmounts[holder][_types.at(i)];
        }
        return amounts;
    }


    /// Write methods

    /// @notice Opens a lootbox token, rolling for a drop and burning the lootbox
    /// @param tokenId Identifier of the lootbox token to open
    function open(uint256 tokenId) public {
        address user = _requireOwned(tokenId);
        if (user != _msgSender()) {
            revert ERC721InvalidOwner(user);
        }
        _open(tokenId);
    }


    /// External methods

    /// @notice Mints a new lootbox token of a specific type to a receiver
    /// @dev Only callable by accounts with MINTER_ROLE
    /// @param receiver Address to receive the minted token
    /// @param typeId Identifier of the token type to mint
    /// @return newTokenId Identifier of the newly minted token
    function mint(address receiver, uint256 typeId) external onlyRole(MINTER_ROLE) returns (uint256 newTokenId) {
        _requireTypeExists(typeId);
        newTokenId = _tokenIndex++;

        _mint(receiver, newTokenId);
        emit TokenMinted(typeId, receiver, newTokenId, _typeCount[typeId]);
    }

    /// @notice Burns a token owned by a holder
    /// @dev Only callable by accounts with BURNER_ROLE
    /// @param holder Address of the token holder
    /// @param tokenId Identifier of the token to burn
    function burn(address holder, uint256 tokenId) external onlyRole(BURNER_ROLE) {
        address realOwner = _requireOwned(tokenId);
        if (holder != realOwner) {
            revert ERC721IncorrectOwner(holder, tokenId, realOwner);
        }

        _burnToken(tokenId);
    }

    /// @notice Opens a lootbox token on behalf of a holder, rolling for a drop and burning the lootbox
    /// @dev Only callable by accounts with BURNER_ROLE
    /// @param holder Address of the token holder
    /// @param tokenId Identifier of the lootbox token to open
    function openFor(address holder, uint256 tokenId) external onlyRole(BURNER_ROLE) {
        address user = _requireOwned(tokenId);
        if (user != holder) {
            revert ERC721InvalidOwner(user);
        }
        _open(tokenId);
    }

    /// @notice Checks if the contract supports a given interface
    /// @param interfaceId Interface identifier (ERC-165)
    /// @return True if the interface is supported, false otherwise
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721, AccessControl) returns (bool) {
        return
            ERC721.supportsInterface(interfaceId)
            || AccessControl.supportsInterface(interfaceId);
    }


    /// Admin methods

    /// @notice Adds a new token type with a name and URI
    /// @dev Only callable by accounts with EDITOR_ROLE
    /// @param typeName Name of the new token type
    /// @param typeURI Metadata URI of the new token type
    /// @return newTypeId Identifier of the newly added token type
    function addType(string calldata typeName, string calldata typeURI) public onlyRole(EDITOR_ROLE) returns (uint256 newTypeId) {
        return _addType(typeName, typeURI);
    }

    /// @notice Removes a token type if it is not currently in use
    /// @dev Only callable by accounts with EDITOR_ROLE
    /// @param typeId Identifier of the token type to remove
    function removeType(uint256 typeId) public onlyRole(EDITOR_ROLE) {
        _requireTypeExists(typeId);
        require(_typeCount[typeId] == 0, "Type already in use");
        _clearDrop(typeId);
        _types.remove(typeId);

        emit TypeRemoved(typeId);
    }

    /// @notice Clears all drop chances associated with a token type
    /// @dev Only callable by accounts with EDITOR_ROLE
    /// @param typeId Identifier of the token type
    function clearDrop(uint256 typeId) public onlyRole(EDITOR_ROLE) {
        _clearDrop(typeId);
    }

    /// @notice Updates the name and URI of an existing token type
    /// @dev Only callable by accounts with EDITOR_ROLE
    /// @param typeId Identifier of the token type to update
    /// @param typeName New name for the token type
    /// @param typeURI New metadata URI for the token type
    function updateType(uint256 typeId, string calldata typeName, string calldata typeURI) public onlyRole(EDITOR_ROLE) {
        _requireTypeExists(typeId);
        _typeName[typeId] = typeName;
        _typeURI[typeId] = typeURI;

        emit TypeUpdated(typeId, typeName, typeURI);
    }


    /// Internal methods

    function _addType(string memory typeName, string memory typeURI) internal returns (uint256 newTypeId) {
        newTypeId = _typesIndex++;
        _types.add(newTypeId);
        _typeName[newTypeId] = typeName;
        _typeURI[newTypeId] = typeURI;

        emit TypeAdded(newTypeId, typeName, typeURI);
    }

    function _addDrop(uint256 typeId, DropChance memory drop) internal returns (uint256 newDropId) {
        _typeDrop[typeId].push(drop);
        newDropId = _typeDrop[typeId].length;
        emit TypeDropAdded(typeId, newDropId, drop);
        return newDropId;
    }

    function _clearDrop(uint256 typeId) internal {
        _requireTypeExists(typeId);
        delete _typeDrop[typeId];
        emit TypeDropCleared(typeId);
    }

    function _requireTypeExists(uint256 typeId) internal view {
        require(_types.contains(typeId), "Type is not exists");
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

    function _open(uint256 tokenId) internal {
        address holder = _requireOwned(tokenId);
        uint256 typeId = _tokenType[tokenId];
        uint256 rarity = _rollDrop(typeId);
        DropChance storage drop = _typeDrop[typeId][rarity];
        uint256 nftItemId = IALFALootbox(drop.tokenAddress).mint(holder, drop.typeId);
        emit DropRolled(holder, typeId, tokenId, drop.tokenAddress, drop.typeId, nftItemId);
        /// Burn lootbox
        _burnToken(tokenId);
    }

    function _burnToken(uint256 tokenId) internal {
        address holder = _requireOwned(tokenId);
        uint256 typeId = _tokenType[tokenId];

        _burn(tokenId);
        emit TokenBurned(typeId, holder, tokenId, _typeCount[typeId]);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        uint256 typeId = _tokenType[tokenId];

        if (from == address(0)) {
            _typeCount[typeId]++;
        } else {
            _holderAmounts[from][typeId]--;
            _holderTokens[from].remove(tokenId);
        }

        super._update(to, tokenId, auth);

        if (to == address(0)) {
            _typeCount[typeId]--;
        } else {
            _holderAmounts[to][typeId]++;
            _holderTokens[to].add(tokenId);
        }

        return from;
    }

}