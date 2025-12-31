// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/token/IDaoRewardManager.sol";
import "../interfaces/staking/pancake/IPancakeV3Pool.sol";
import "../interfaces/staking/pancake/IV3NonfungiblePositionManager.sol";
import "../interfaces/staking/pancake/IPancakeV3SwapCallback.sol";
import "../interfaces/staking/IEventFundingManager.sol";

import "./EventFundingManager.sol";
import "../utils/SwapHelper.sol";

import {NodeManagerStorage} from "./NodeManagerStorage.sol";

contract NodeManager is Initializable, OwnableUpgradeable, PausableUpgradeable, NodeManagerStorage {
    using SafeERC20 for IERC20;
    using SwapHelper for *;

    modifier onlyDistributeRewardManager() {
        require(msg.sender == address(distributeRewardAddress), "onlyDistributeRewardManager");
        _;
    }

    constructor(){
        _disableInitializers();
    }

    /**
     * @dev 初始化合约
     * @param initialOwner 初始所有者地址
     * @param _daoRewardManager DAO 奖励管理合约地址
     * @param _underlyingToken 底层代币地址
     * @param _usdt usdt
     * @param _distributeRewardAddress 奖励分发管理地址
     * @param _eventFundingManager 事件资金管理合约地址
     */
    function initialize(address initialOwner, address _daoRewardManager, address _underlyingToken,address _usdt, address _distributeRewardAddress, address _eventFundingManager) public initializer {
        __Ownable_init(initialOwner);
        daoRewardManager = IDaoRewardManager(_daoRewardManager);
        underlyingToken = _underlyingToken;
        USDT = _usdt;
        distributeRewardAddress = _distributeRewardAddress;
        eventFundingManager = IEventFundingManager(_eventFundingManager);
    }

    /**
     * @dev 设置交易池地址
     * @param _pool Pancake V3 交易池地址
     */
    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Invalid pool address");
        pool = _pool;
    }

    /**
     * @dev 设置流动性仓位 NFT ID
     * @param _tokenId Pancake V3 流动性仓位的 NFT Token ID
     */
    function setPositionTokenId(uint256 _tokenId) external onlyOwner {
        require(_tokenId > 0, "Invalid token ID");
        positionTokenId = _tokenId;
    }

    /**
     * @dev 购买节点
     * @param amount 购买节点所需的代币数量，必须匹配分布式节点或集群节点的价格
     */
    function purchaseNode(uint256 amount) external {
        if (nodeBuyerInfo[msg.sender].amount > 0) {
            revert HaveAlreadyBuyNode(msg.sender);
        }

        uint8 buyNodeType = matchNodeTypeByAmount(amount);

        IERC20(USDT).safeTransferFrom(msg.sender, address(this), amount);

        NodeBuyerInfo memory buyerInfo = NodeBuyerInfo({
            buyer: msg.sender,
            nodeType: buyNodeType,
            amount: amount
        });

        nodeBuyerInfo[msg.sender] = buyerInfo;

        emit PurchaseNodes({
            buyer: msg.sender,
            amount: amount,
            nodeType: buyNodeType
        });
    }

    /**
     * @dev 分发节点奖励（仅奖励分发管理器可调用）
     * @param recipient 接收奖励的地址
     * @param amount 奖励金额
     * @param incomeType 收益类型（0-节点收益, 1-推广收益）
     */
    function distributeRewards(address recipient, uint256 amount, uint8 incomeType) external onlyDistributeRewardManager {
        require(recipient != address(0), "NodeManager.distributeRewards: zero address");
        require(amount > 0, "NodeManager.distributeRewards: amount must more than zero");
        require(incomeType <= uint256(NodeIncomeType.PromoteProfit), "Invalid income type");

        nodeRewardTypeInfo[recipient][incomeType].amount += amount;

        emit DistributeNodeRewards({
            recipient: recipient,
            amount: amount,
            incomeType: incomeType
        });
    }

    /**
     * @dev 领取节点奖励
     * @param incomeType 收益类型（0-节点收益, 1-推广收益）
     * @notice 20% 的奖励将被强制扣留并转换为 USDT 存入事件预测市场
     */
    function claimReward(uint8 incomeType) external {
        require(incomeType <= uint256(NodeIncomeType.PromoteProfit), "Invalid income type");
        uint256 rewardAmount = nodeRewardTypeInfo[msg.sender][incomeType].amount;
        nodeRewardTypeInfo[msg.sender][incomeType].amount = 0;

        uint256 toEventPredictionAmount = (rewardAmount * 20) / 100;

        if (toEventPredictionAmount > 0) {
            daoRewardManager.withdraw(address(this), toEventPredictionAmount);

            uint256 usdtAmount = SwapHelper.swapTokenToUsdt(
                pool,
                underlyingToken,
                USDT,
                toEventPredictionAmount,
                address(this)
            );

            IERC20(USDT).approve(address(eventFundingManager), usdtAmount);
            eventFundingManager.depositUsdt(usdtAmount);
        }

        uint256 canWithdrawAmount = rewardAmount - toEventPredictionAmount;
        daoRewardManager.withdraw(msg.sender, canWithdrawAmount);
    }

    /**
     * @dev 添加流动性到 Pancake V3 池（仅所有者可调用）
     * @param amount 要添加的 USDT 总量
     * @notice 将 50% 的 USDT 兑换为底层代币，然后添加流动性
     */
    function addLiquidity(uint256 amount) external onlyOwner {
        require(pool != address(0), "Pool not set");
        require(amount > 0, "Amount must be greater than 0");
        require(positionTokenId > 0, "Position token not initialized");

        uint256 swapAmount = amount / 2;
        uint256 remainingAmount = amount - swapAmount;
        IERC20(USDT).approve(POSITION_MANAGER, amount);

        uint256 underlyingTokenReceived = SwapHelper.swapUsdtToToken(
            pool,
            USDT,
            underlyingToken,
            swapAmount,
            address(this)
        );

        uint256 underlyingTokenBalance = underlyingTokenReceived;
        uint256 usdtBalance = remainingAmount;

        IERC20(underlyingToken).approve(POSITION_MANAGER, underlyingTokenBalance);
        bool zeroForOne = USDT < underlyingToken;
        uint256 amount0Desired;
        uint256 amount1Desired;
        if (zeroForOne) {
            amount0Desired = usdtBalance;
            amount1Desired = underlyingTokenBalance;
        } else {
            amount0Desired = underlyingTokenBalance;
            amount1Desired = usdtBalance;
        }

        IV3NonfungiblePositionManager.IncreaseLiquidityParams memory params =
            IV3NonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: (amount0Desired * SLIPPAGE_TOLERANCE) / 100,
                amount1Min: (amount1Desired * SLIPPAGE_TOLERANCE) / 100,
                deadline: block.timestamp + 15 minutes
            });
        (uint128 liquidityAdded, uint256 amount0Used, uint256 amount1Used) =
            IV3NonfungiblePositionManager(POSITION_MANAGER).increaseLiquidity(params);

        emit LiquidityAdded(positionTokenId, liquidityAdded, amount0Used, amount1Used);
    }

    /**
     * @dev Pancake V3 交换回调函数
     * @param amount0Delta token0 的变化量
     * @param amount1Delta token1 的变化量
     * @param data 回调数据
     */
    function pancakeV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        require(msg.sender == pool, "Invalid callback caller");
        SwapHelper.handleSwapCallback(pool, amount0Delta, amount1Delta, msg.sender);
    }

    /**
     * @dev 根据金额匹配节点类型
     * @param amount 购买金额
     * @return 节点类型（0-分布式节点, 1-集群节点）
     */
    function matchNodeTypeByAmount(uint256 amount) internal view returns (uint8)  {
        uint8 buyNodeType;
        if (amount == buyDistributedNode) {
            buyNodeType = uint8(NodeType.DistributedNode);
        } else if (amount == buyClusterNode) {
            buyNodeType = uint8(NodeType.ClusterNode);
        } else {
            revert InvalidNodeTypeError(amount);
        }
        return buyNodeType;
    }
}
