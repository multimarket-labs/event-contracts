// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface INodeManager {
    enum NodeType {
        DistributedNode,
        ClusterNode
    }

    enum NodeIncomeType {
        NodeTypeProfit,
        TradeFeeProfit,
        ChildCoinProfit,
        SecondTierMarketProfit,
        PromoteProfit
    }

    struct NodeBuyerInfo {
        address buyer;
        uint8   nodeType;
        uint256 amount;
    }

    struct NodeRewardInfo {
        address recipient;
        uint256 amount;
        uint8   incomeType;
    }

    event PurchaseNodes (
        address indexed buyer,
        uint256 amount,
        uint8 nodeType
    );

    event DistributeNodeRewards (
        address indexed recipient,
        uint256 amount,
        uint8 incomeType
    );

    event LiquidityAdded (
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    error InvalidNodeTypeError(uint256 amount);
    error HaveAlreadyBuyNode(address buyer);


    function purchaseNode(uint256 amount) external;
    function distributeRewards(address recipient, uint256 amount, uint8 incomeType) external;
    function claimReward(uint8 incomeType,uint rewardAmount) external;
    function addLiquidity(uint256 amount) external;
}
