// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IChooseMeToken {
    function burn(address user, uint256 _amount) external;
    function quote(uint256 amount) external view returns (uint256);

    event Burn(uint256 _burnAmount, uint256 _totalSupply);
    event SetStakingManager(address indexed stakingManager);
    event SetPoolAddress(ChooseMePool indexed pool);

    event TradeSlipage(
        uint256 amount, uint256 nodeFee, uint256 clusterFee, uint256 marketFee, uint256 techFee, uint256 subFee
    );
    event ProfitSlipage(
        uint256 amount, uint256 nodeFee, uint256 clusterFee, uint256 marketFee, uint256 techFee, uint256 subFee
    );
    event AllocateSlipageU(uint256 uAmount, uint256 marketFee, uint256 techFee, uint256 subFee);

    struct ChooseMePool {
        address nodePool; // Base pool (node income pool)
        address daoRewardPool; // DAO organization rewards
        address airdropPool; // Airdrop
        address techRewardsPool; // Technical
        address foundingStrategyPool; // Capital strategy
        address marketingPool; // Marketing development
        address subTokenPool; // Sub token liquidity pool
    }

    struct ChooseMeTradeFee {
        uint16 nodeFee; // Node pool fee
        uint16 clusterFee; // Cluster pool fee
        uint16 marketFee; // Market development fee
        uint16 techFee; // Technical fee
        uint16 subTokenFee; // Sub token liquidity fee
    }

    struct ChooseMeProfitFee {
        uint16 nodeFee; // Node pool fee
        uint16 clusterFee; // Cluster pool fee
        uint16 marketFee; // Market development fee
        uint16 techFee; // Technical fee
        uint16 subTokenFee; // Sub token liquidity fee
    }

    struct CumulativeSlipage {
        uint256 nodeFee; // Node pool fee
        uint256 clusterFee; // Cluster pool fee
        uint256 marketFee; // Market development fee
        uint256 techFee; // Technical fee
        uint256 subTokenFee; // Sub token liquidity fee
    }
}
