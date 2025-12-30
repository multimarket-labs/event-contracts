// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/token/IChooseMeToken.sol";


abstract contract ChooseMeTokenStorage is IChooseMeToken{
    uint256 public constant MaxTotalSupply = 1_000_000_000 * 10 ** 6;

    uint256 public _lpBurnedTokens;

    address public daoRewardPool;

    bool internal isAllocation;

    struct chooseMePool {
        address  nodePool;                 // 底池(节点收入加池子)
        address  daoRewardPool;            // dao 组织奖励
        address  airdropPool;              // 空投
        address  techRewardsPool;          // 技术
        address  ecosystemPool;            // 生态合作
        address  foundingStrategyPool;     // 资本战略
        address  marketingDevelopmentPool; // 市场发展
    }

    chooseMePool public cmPool;

    event Burn(
        uint256 _burnAmount,
        uint256 _totalSupply
    );

    uint256[100] private __gap;
}
