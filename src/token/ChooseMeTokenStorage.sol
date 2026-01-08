// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/token/IChooseMeToken.sol";

abstract contract ChooseMeTokenStorage is IChooseMeToken {
    uint256 public constant MaxTotalSupply = 1_000_000_000 * 10 ** 6;

    uint256 public _lpBurnedTokens;

    address public stakingManager;

    bool internal isAllocation;

    struct chooseMePool {
        address normalPool; // Base pool (node income pool)
        address nodePool; // Base pool (node income pool)
        address daoRewardPool; // DAO organization rewards
        address airdropPool; // Airdrop
        address techRewardsPool; // Technical
        address ecosystemPool; // Ecosystem collaboration
        address foundingStrategyPool; // Capital strategy
        address marketingDevelopmentPool; // Marketing development
        address subTokenPool; // Sub token liquidity pool
    }

    chooseMePool public cmPool;

    struct chooseMeTradeFee {
        uint16 nodeFee; // Node pool fee
        uint16 clusterFee; // Cluster pool fee
        uint16 marketFee; // Market development fee
        uint16 techFee; // Technical fee
        uint16 subTokenFee; // Sub token liquidity fee
    }

    chooseMeTradeFee public tradeFee;

    struct chooseMeProfitFee {
        uint16 normalFee; // Central fee
        uint16 nodeFee; // Node pool fee
        uint16 clusterFee; // Cluster pool fee
        uint16 marketFee; // Market development fee
        uint16 techFee; // Technical fee
        uint16 subTokenFee; // Sub token liquidity fee
    }

    chooseMeProfitFee public profitFee;

    event Burn(uint256 _burnAmount, uint256 _totalSupply);
    event SetStakingManager(address indexed stakingManager);
    event SetPoolAddress(chooseMePool indexed pool);

    event TradeSlipage(
        uint256 amount, uint256 nodeFee, uint256 clusterFee, uint256 marketFee, uint256 techFee, uint256 subFee
    );
    event ProfitSlipage(
        uint256 amount,
        uint256 normalFee,
        uint256 nodeFee,
        uint256 clusterFee,
        uint256 marketFee,
        uint256 techFee,
        uint256 subFee
    );

    address public router;
    address public mainPair;

    uint256 public marketOpenTime;

    mapping(address => uint) public userCost; // user cost u amount

    EnumerableSet.AddressSet whiteList;

    uint256[100] private __gap;
}
