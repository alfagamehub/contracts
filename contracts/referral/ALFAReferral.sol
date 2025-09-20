// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IALFAReferral, ReferralPercents} from "./interfaces/IALFAReferral.sol";
import {PERCENT_PRECISION} from "../const.sol";

contract ALFAReferral is AccessControl, IALFAReferral {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 public constant CONNECTOR_ROLE = keccak256("CONNECTOR_ROLE");

    mapping(address child => address parent) private _parents;
    mapping(address parent => EnumerableSet.AddressSet children) private _children;

    uint256[] private _percents = [80000, 40000, 20000, 10000, 10000];

    /// @notice Contract constructor. Grants admin and connector roles to contract deployer.
    /// @dev Grants DEFAULT_ADMIN_ROLE and CONNECTOR_ROLE to the deployer address.
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(CONNECTOR_ROLE, _msgSender());
    }

    /// @notice Returns the referral percent structure for a given child address.
    /// @dev Traverses up the referral tree from the child, returning each parent and their percent.
    /// @param childAddress The address of the child whose referral percents are being queried.
    /// @return result An array of ReferralPercents structs containing parent addresses and percents.
    function getReferralPercents(address childAddress) external view returns (ReferralPercents[] memory) {
        ReferralPercents[] memory result = new ReferralPercents[](_percents.length);
        address parent = _parents[childAddress];
        for (uint256 i; i < _percents.length; i++) {
            result[i].parentAddress = parent;
            result[i].percents = _percents[i];
            parent = _parents[parent];
        }
        return result;
    }

    /// @notice Returns the parent address for a given child.
    /// @dev Returns address(0) if the child has no parent.
    /// @param childAddress The address of the child whose parent is being queried.
    /// @return The parent address of the specified child.
    function getParent(address childAddress) public view returns (address) {
        return _parents[childAddress];
    }

    /// @notice Returns the number of children for a given parent.
    /// @dev Returns zero if the parent has no children.
    /// @param parentAddress The address of the parent whose children count is being queried.
    /// @return The number of children addresses linked to the parent.
    function getChildrenCount(address parentAddress) public view returns (uint256) {
        return _children[parentAddress].length();
    }

    /// @notice Returns a paginated list of children addresses for a given parent.
    /// @dev Returns an empty array if offset is greater than or equal to the number of children.
    /// @param parentAddress The address of the parent whose children are being queried.
    /// @param offset The starting index in the children list.
    /// @param limit The maximum number of children addresses to return.
    /// @return An array of child addresses belonging to the parent.
    function getChildren(address parentAddress, uint256 offset, uint256 limit) public view returns (address[] memory) {
        uint256 count = getChildrenCount(parentAddress);
        if (offset >= count) return new address[](0);
        count -= offset;
        uint256 length = count < limit
            ? count
            : limit;
        address[] memory children = new address[](length);
        for (uint256 i = offset; i < offset + limit; i++) {
            children[i - offset] = _children[parentAddress].at(i);
        }
        return children;
    }

    /// @notice Adds a referral relation between a parent and a child address.
    /// @dev Removes any existing parent relation for the child before adding the new one.
    ///      Only callable by accounts with CONNECTOR_ROLE.
    /// @param parentAddress The address to be set as the parent.
    /// @param childAddress The address to be set as the child.
    function addRelation(address parentAddress, address childAddress) public onlyRole(CONNECTOR_ROLE) {
        _removeRelation(childAddress);
        _parents[childAddress] = parentAddress;
        _children[parentAddress].add(childAddress);
        emit RelationAdded(parentAddress, childAddress);
    }

    /// @notice Sets the referral percents for each referral level.
    /// @dev Only callable by accounts with DEFAULT_ADMIN_ROLE.
    ///      Percents should use PERCENT_PRECISION for scaling.
    /// @param percents An array of percent values for each referral level.
    function setPercents(uint256[] calldata percents) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _percents = percents;
        emit PercentsSet(percents);
    }

    function _removeRelation(address childAddress) internal {
        address parentAddress = _parents[childAddress];
        if (parentAddress != address(0)) {
            delete _parents[childAddress];
            _children[parentAddress].remove(childAddress);
            emit RelationRemoved(parentAddress, childAddress);
        }
    }

}