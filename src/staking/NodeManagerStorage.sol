// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/staking/INodeManager.sol";
import "../interfaces/token/IDaoRewardManager.sol";
import "../interfaces/staking/IEventFundingManager.sol";


abstract contract NodeManagerStorage is INodeManager {
    uint256 public constant buyDistributedNode = 500 * 10 ** 18;
    uint256 public constant buyClusterNode = 1000 * 10 ** 18;

    address public constant POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    uint256 public constant SLIPPAGE_TOLERANCE = 95;

    address public constant V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    uint8 public poolType;  // 1 pancake v2 liquidity; 2 pancake v3 liquidity ; 

    address public USDT;
    address public underlyingToken;
    address public distributeRewardAddress;
    address public pool;
    uint256 public positionTokenId; // NFT position token ID

    IDaoRewardManager public daoRewardManager;
    IEventFundingManager public eventFundingManager;

    mapping(address => NodeBuyerInfo) public nodeBuyerInfo;

    mapping(address => mapping(uint8 => NodeRewardInfo)) public nodeRewardTypeInfo;

    uint256[100] private __gap;
}
