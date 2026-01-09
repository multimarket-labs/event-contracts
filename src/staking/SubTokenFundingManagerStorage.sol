// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/staking/ISubTokenFundingManager.sol";


abstract contract SubTokenFundingManagerStorage is ISubTokenFundingManager {

    address public constant POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    uint256 public constant SLIPPAGE_TOLERANCE = 95;
    address public pool;
    uint256 public positionTokenId;

    address public constant V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    uint8 public poolType;  // 1 pancake v2 liquidity; 2 pancake v3 liquidity ; 

    address public underlyingToken;
    address public USDT;

    address public operatorManager;

    uint256[100] private __gap;
}
