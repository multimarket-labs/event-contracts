// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/token/IChooseMeToken.sol";


abstract contract ChooseMeTokenStorage is IChooseMeToken{
    uint256 public constant MaxTotalSupply = 1_000_000_000 * 10 ** 6;

    uint256 public _lpBurnedTokens;

    address public stakingManager;

    bool internal isAllocation;

    struct chooseMePool {
        address  nodePool;                 // Base pool (node income pool)
        address  daoRewardPool;            // DAO organization rewards
        address  airdropPool;              // Airdrop
        address  techRewardsPool;          // Technical
        address  ecosystemPool;            // Ecosystem collaboration
        address  foundingStrategyPool;     // Capital strategy
        address  marketingDevelopmentPool; // Marketing development
    }

    chooseMePool public cmPool;

    event Burn(
        uint256 _burnAmount,
        uint256 _totalSupply
    );

    uint256[100] private __gap;
}
