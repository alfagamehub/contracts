// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721, IERC721, IERC165, IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl, IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IALFAKey, TokenType, HolderToken} from "./IALFAKey.sol";

/// @title ALFA Key NFT
/// @notice Typed NFT
contract ALFAKey is ERC721, AccessControl, IALFAKey {

    using EnumerableSet for EnumerableSet.UintSet;

    bytes32 public constant EDITOR_ROLE = keccak256("EDITOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    
    uint256 internal _typesIndex = 1;
    uint256 internal _tokenIndex = 1;

    EnumerableSet.UintSet internal _types;
    mapping(uint256 typeId => string typeName) internal _typeName;
    mapping(uint256 typeId => string typeURI) internal _typeURI;
    mapping(uint256 typeId => uint256 count) internal _typeCount;

    mapping(uint256 tokenId => uint256 typeId) internal _tokenType;
    mapping(address holder => EnumerableSet.UintSet tokens) internal _holderTokens;
    mapping(address holder => mapping (uint256 typeId => uint256 amount)) internal _holderAmounts;

    /// @notice Initializes the ALFAKey contract with predefined token types and assigns roles to the deployer
    /// @dev Grants DEFAULT_ADMIN_ROLE and EDITOR_ROLE to the deployer and adds initial token types
    constructor() ERC721("ALFA Key", "ALKEY") {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _msgSender());
        _grantRole(BURNER_ROLE, _msgSender());
        _grantRole(EDITOR_ROLE, _msgSender());

        _addType("Green Gorilla", "https://api.alfagame.xyz/static/keys/green.mp4");
        _addType("Blue Cobra", "https://api.alfagame.xyz/static/keys/blue.mp4");
        _addType("Yellow Bear", "https://api.alfagame.xyz/static/keys/yellow.mp4");
        _addType("Red Tiger", "https://api.alfagame.xyz/static/keys/red.mp4");
        _addType("Violet Dragon", "https://api.alfagame.xyz/static/keys/violet.mp4");
    }


    /// Read methods

    /// @notice Returns the list of all token types with their metadata and counts
    /// @return An array of TokenType structs representing all existing token types
    function getTypes() public view returns (TokenType[] memory) {
        uint256 length = _types.length();
        TokenType[] memory list = new TokenType[](length);
        for (uint256 i; i < length; i++) {
            list[i].typeId = _types.at(i);
            list[i].count = _typeCount[list[i].typeId];
            list[i].typeName = _typeName[list[i].typeId];
            list[i].typeURI = _typeURI[list[i].typeId];
        }
        return list;
    }

    /// @notice Returns a paginated list of tokens owned by a specific holder
    /// @param holder The address of the token holder
    /// @param offset The starting index from which to return tokens
    /// @param limit The maximum number of tokens to return
    /// @return An array of HolderToken structs representing the holder's tokens in the specified range
    /// @return count The total count of tokens owned by the holder
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

    /// @notice Returns the URI of the token's image based on its type
    /// @param tokenId The identifier of the token
    /// @return The URI string of the token's image
    function tokenURI(uint256 tokenId) public view override(ERC721, IERC721Metadata) returns (string memory) {
        _requireOwned(tokenId);
        return _typeURI[tokenTypeId(tokenId)];
    }

    /// @notice Returns detailed information about the token's type
    /// @param tokenId The identifier of the token
    /// @return data A TokenType struct containing metadata about the token's type
    function tokenType(uint256 tokenId) public view returns (TokenType memory data) {
        uint256 typeId = tokenTypeId(tokenId);

        data.typeId = typeId;
        data.count = _typeCount[typeId];
        data.typeName = _typeName[typeId];
        data.typeURI = _typeURI[typeId];
    }

    /// @notice Returns the type identifier of a specific token
    /// @param tokenId The identifier of the token
    /// @return The typeId associated with the token
    function tokenTypeId(uint256 tokenId) public view returns (uint256) {
        _requireOwned(tokenId);
        return _tokenType[tokenId];
    }

    /// @notice Returns the total number of tokens of a specified type
    /// @param typeId The identifier of the token type
    /// @return The total count of tokens of the specified type
    function getTypeAmount(uint256 typeId) public view returns (uint256) {
        return _typeCount[typeId];
    }

    /// @notice Returns the number of tokens of a specified type owned by a given holder
    /// @param holder The address of the token holder
    /// @param typeId The identifier of the token type
    /// @return The count of tokens of the specified type owned by the holder
    function getTypeHolderAmount(address holder, uint256 typeId) public view returns (uint256) {
        return _holderAmounts[holder][typeId];
    }

    /// @notice Returns an array of token counts owned by a holder, separated by each token type
    /// @param holder The address of the token holder
    /// @return An array of uint256 representing the count of tokens per type owned by the holder
    function getHolderAmounts(address holder) public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](_types.length());
        for (uint256 i; i < _types.length(); i++) {
            amounts[i] = _holderAmounts[holder][_types.at(i)];
        }
        return amounts;
    }


    /// External methods

    /// @notice Mints a new token of a specified type to a receiver address
    /// @dev Caller must have MINTER_ROLE
    /// @param receiver The address to receive the minted token
    /// @param typeId The type identifier of the token to mint
    /// @return newTokenId The identifier of the newly minted token
    function mint(address receiver, uint256 typeId) external onlyRole(MINTER_ROLE) returns (uint256 newTokenId) {
        _requireTypeExists(typeId);
        newTokenId = _tokenIndex++;

        _tokenType[newTokenId] = typeId;
        _mint(receiver, newTokenId);
        emit TokenMinted(typeId, receiver, newTokenId, _typeCount[typeId]);
    }

    /// @notice Burns a token owned by a holder
    /// @dev Caller must have BURNER_ROLE; the holder must be the actual owner of the token
    /// @param holder The address of the token holder
    /// @param tokenId The identifier of the token to burn
    function burn(address holder, uint256 tokenId) external onlyRole(BURNER_ROLE) {
        address realOwner = _requireOwned(tokenId);
        if (holder != realOwner) {
            revert ERC721IncorrectOwner(holder, tokenId, realOwner);
        }
        uint256 typeId = _tokenType[tokenId];

        _burn(tokenId);
        emit TokenBurned(typeId, holder, tokenId, _typeCount[typeId]);
    }

    /// @notice Checks if the contract supports a given interface
    /// @param interfaceId The interface identifier to check
    /// @return True if the interface is supported, false otherwise
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721, AccessControl) returns (bool) {
        return
            ERC721.supportsInterface(interfaceId)
            || AccessControl.supportsInterface(interfaceId);
    }


    /// Admin methods

    /// @notice Adds a new token type with a name and URI
    /// @dev Caller must have EDITOR_ROLE
    /// @param typeName The name of the new token type
    /// @param typeURI The URI associated with the new token type
    /// @return newTypeId The identifier of the newly added token type
    function addType(string calldata typeName, string calldata typeURI) public onlyRole(EDITOR_ROLE) returns (uint256 newTypeId) {
        return _addType(typeName, typeURI);
    }

    /// @notice Removes an existing token type if it has no tokens in use
    /// @dev Caller must have EDITOR_ROLE; type count must be zero
    /// @param typeId The identifier of the token type to remove
    function removeType(uint256 typeId) public onlyRole(EDITOR_ROLE) {
        _requireTypeExists(typeId);
        require(_typeCount[typeId] == 0, "Type already in use");
        _types.remove(typeId);

        emit TypeRemoved(typeId);
    }

    /// @notice Updates the name and URI of an existing token type
    /// @dev Caller must have EDITOR_ROLE
    /// @param typeId The identifier of the token type to update
    /// @param typeName The new name for the token type
    /// @param typeURI The new URI for the token type
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

    function _requireTypeExists(uint256 typeId) internal view {
        require(_types.contains(typeId), "Type is not exists");
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