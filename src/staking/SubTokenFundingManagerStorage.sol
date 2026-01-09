// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/staking/ISubTokenFundingManager.sol";

abstract contract SubTokenFundingManagerStorage is ISubTokenFundingManager {
    address public constant V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    address public USDT;
    address public subToken;

    address public operatorManager;

    uint256[100] private __gap;
}
