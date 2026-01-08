// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/token/IChooseMeToken.sol";


abstract contract ChooseMeTokenStorage is IChooseMeToken{
    uint256 public constant MaxTotalSupply = 1_000_000_000 * 10 ** 6;
    
    address public constant POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;

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
        address  subTokenPool;             // Sub token liquidity pool
    }

    chooseMePool public cmPool;

    event Burn(
        uint256 _burnAmount,
        uint256 _totalSupply
    );

    address public factory;
    uint public tradeFeeRate; // trade fee rate, 300 means 3 %

    uint256[100] private __gap;
}
