// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/token/IChooseMeToken.sol";

abstract contract ChooseMeTokenStorage is IChooseMeToken {
    uint256 public constant MaxTotalSupply = 1_000_000_000 * 10 ** 6;

    address public USDT;
    address public constant V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant V2_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    uint256 public _lpBurnedTokens;

    address public stakingManager;

    address public currencyDistributor;

    bool internal isAllocation;

    ChooseMePool public cmPool;

    ChooseMeTradeFee public tradeFee;

    ChooseMeProfitFee public profitFee;

    address public mainPair;
    bool internal slippageLock;

    mapping(address => uint256) public userCost;

    CumulativeSlipage public cumulativeSlipage;

    EnumerableSet.AddressSet whiteList;

    EnumerableSet.AddressSet marketingPools; // Marketing developments
    EnumerableSet.AddressSet ecosystemPools; // Ecosystem pools

    uint256[100] private __gap;
}
