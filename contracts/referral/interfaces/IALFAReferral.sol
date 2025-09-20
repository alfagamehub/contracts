// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IALFAReferralPercents, ReferralPercents} from "./IALFAReferralPercents.sol";

interface IALFAReferral is IALFAReferralPercents {

    event RelationAdded(address indexed parent, address indexed child);
    event RelationRemoved(address indexed parent, address indexed child);
    event PercentsSet(uint256[] percents);
    
    function addRelation(address parentAddress, address childAddress) external;

    function getParent(address childAddress) external view returns (address);
    function getChildrenCount(address parentAddress) external view returns (uint256);
    function getChildren(address parentAddress, uint256 offset, uint256 limit) external view returns (address[] memory);

}