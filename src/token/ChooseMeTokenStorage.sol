// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/token/IChooseMeToken.sol";

abstract contract ChooseMeTokenStorage is IChooseMeToken {
    uint256 public constant MaxTotalSupply = 1_000_000_000 * 10 ** 6;

    address public constant V3_POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    address public constant V3_FACTORY = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    address public USDT;
    address public constant V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant V2_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    uint256 public _lpBurnedTokens;

    address public stakingManager;

    bool internal isAllocation;

    struct ChooseMePool {
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

    ChooseMePool public cmPool;

    struct ChooseMeTradeFee {
        uint16 nodeFee; // Node pool fee
        uint16 clusterFee; // Cluster pool fee
        uint16 marketFee; // Market development fee
        uint16 techFee; // Technical fee
        uint16 subTokenFee; // Sub token liquidity fee
    }

    ChooseMeTradeFee public tradeFee;

    struct ChooseMeProfitFee {
        uint16 normalFee; // Central fee
        uint16 nodeFee; // Node pool fee
        uint16 clusterFee; // Cluster pool fee
        uint16 marketFee; // Market development fee
        uint16 techFee; // Technical fee
        uint16 subTokenFee; // Sub token liquidity fee
    }

    ChooseMeProfitFee public profitFee;

    event Burn(uint256 _burnAmount, uint256 _totalSupply);
    event SetStakingManager(address indexed stakingManager);
    event SetPoolAddress(ChooseMePool indexed pool);

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

    address public mainPair;

    uint256 public marketOpenTime;

    mapping(address => uint256) public userCost; // user cost u amount

    EnumerableSet.AddressSet whiteList;

    uint256[100] private __gap;
}
