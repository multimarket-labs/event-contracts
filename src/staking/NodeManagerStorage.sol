// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/staking/INodeManager.sol";
import "../interfaces/staking/pancake/IV3NonfungiblePositionManager.sol";
import "../interfaces/token/IDaoRewardManager.sol";


abstract contract NodeManagerStorage is INodeManager {
    uint256 public constant buyDistributedNode = 500 * 10 ** 6;
    uint256 public constant buyClusterNode = 1000 * 10 ** 6;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    address public constant POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    uint256 public constant SLIPPAGE_TOLERANCE = 95;

    address public underlyingToken;
    address public distributeRewardAddress;
    address public pool;
    uint256 public positionTokenId; // NFT position token ID

    IDaoRewardManager public daoRewardManager;

    mapping(address => NodeBuyerInfo) public nodeBuyerInfo;

    mapping(address => mapping(uint8 => NodeRewardInfo)) public nodeRewardTypeInfo;

    uint256[100] private __gap;
}
