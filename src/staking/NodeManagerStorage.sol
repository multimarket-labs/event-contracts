// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../interfaces/staking/INodeManager.sol";

abstract contract NodeManagerStorage is INodeManager {
    uint256 public constant buyDistributedNode = 500 * 10 ** 6;
    uint256 public constant buyClusterNode = 1000 * 10 ** 6;

    address public underlyingToken;

    address public distributeRewardAddress;

    mapping(address => NodeBuyerInfo) public nodeBuyerInfo;

    mapping(address => mapping(uint8 => NodeRewardInfo)) public nodeRewardTypeInfo;

    uint256[100] private __gap;
}
