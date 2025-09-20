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

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(CONNECTOR_ROLE, _msgSender());
    }

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

    function getParent(address childAddress) public view returns (address) {
        return _parents[childAddress];
    }

    function getChildrenCount(address parentAddress) public view returns (uint256) {
        return _children[parentAddress].length();
    }

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

    function addRelation(address parentAddress, address childAddress) public onlyRole(CONNECTOR_ROLE) {
        _removeRelation(childAddress);
        _parents[childAddress] = parentAddress;
        _children[parentAddress].add(childAddress);
        emit RelationAdded(parentAddress, childAddress);
    }

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