// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/staking/INodeManager.sol";
import "../interfaces/token/IDaoRewardManager.sol";
import "../interfaces/staking/IEventFundingManager.sol";

abstract contract NodeManagerStorage is INodeManager {
    uint256 public constant buyDistributedNode = 500 * 10 ** 18;
    uint256 public constant buyClusterNode = 1000 * 10 ** 18;
    address public constant V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    address public USDT;
    address public underlyingToken;
    address public distributeRewardAddress;

    IDaoRewardManager public daoRewardManager;
    IEventFundingManager public eventFundingManager;

    mapping(address => NodeBuyerInfo) public nodeBuyerInfo;

    mapping(address => mapping(uint8 => NodeRewardInfo)) public nodeRewardTypeInfo;

    mapping(address => RewardClaimInfo) public rewardClaimInfo;

    mapping(address => address) public inviters;

    uint256[100] private __gap;
}
