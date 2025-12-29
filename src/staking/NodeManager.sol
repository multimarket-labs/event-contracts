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

import {NodeManagerStorage} from "./NodeManagerStorage.sol";

contract NodeManager is Initializable, OwnableUpgradeable, PausableUpgradeable, NodeManagerStorage {
    using SafeERC20 for IERC20;

    modifier onlyDistributeRewardManager() {
        require(msg.sender == address(distributeRewardAddress), "onlyDistributeRewardManager");
        _;
    }

    constructor(){
        _disableInitializers();
    }

    function initialize(address initialOwner, IDaoRewardManager _daoRewardManager, address _underlyingToken, address _distributeRewardAddress) public initializer {
        __Ownable_init(initialOwner);
        daoRewardManager = _daoRewardManager;
        underlyingToken = _underlyingToken;
        distributeRewardAddress = _distributeRewardAddress;
    }

    // 设置流动性池地址
    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Invalid pool address");
        pool = _pool;
    }

    // 设置 NFT position token ID
    function setPositionTokenId(uint256 _tokenId) external onlyOwner {
        require(_tokenId > 0, "Invalid token ID");
        positionTokenId = _tokenId;
    }

    function purchaseNode(uint256 amount) external {
        if (nodeBuyerInfo[msg.sender].amount > 0) {
            revert HaveAlreadyBuyNode(msg.sender);
        }

        uint8 buyNodeType = matchNodeTypeByAmount(amount);

        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);

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

    function claimReward(uint8 incomeType) external {
        require(incomeType <= uint256(NodeIncomeType.PromoteProfit), "Invalid income type");
        uint256 rewardAmount = nodeRewardTypeInfo[msg.sender][incomeType].amount;

        uint256 toEventPredictionAmount = (rewardAmount * 20) / 100;

        // todo 20% 兑换成 USDT 打入事件预测市场
        uint256 canWithdrawAmount = rewardAmount - toEventPredictionAmount;

        daoRewardManager.withdraw(msg.sender, canWithdrawAmount);

        nodeRewardTypeInfo[msg.sender][incomeType].amount = 0;
    }

    function addLiquidity(uint256 amount) external onlyOwner {
        // 将所有购买节点的资金用于加 LP, 将这个合约里面的一半的 USDT 买 underlyingToken 代币，添加到流动性池里面
        require(pool != address(0), "Pool not set");
        require(amount > 0, "Amount must be greater than 0");
        require(positionTokenId > 0, "Position token not initialized");

        // 步骤1: 查询交易对池子的汇率价格和代币顺序
        IPancakeV3Pool v3Pool = IPancakeV3Pool(pool);
        (uint160 sqrtPriceX96,,,,,,) = v3Pool.slot0();
        bool zeroForOne = USDT < underlyingToken;
        uint160 sqrtPriceLimitX96;
        if (zeroForOne) {
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 95) / 100);
        } else {
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 105) / 100);
        }

        // 步骤2: 用一半的 amount (USDT) 去买 underlyingToken 代币
        uint256 swapAmount = amount / 2;
        uint256 remainingAmount = amount - swapAmount; // 剩余的一半 USDT

        // 记录 swap 前的 underlyingToken 余额
        uint256 underlyingTokenBefore = IERC20(underlyingToken).balanceOf(address(this));

        IPancakeV3Pool(pool).swap(
            address(this),
            zeroForOne,
            int256(swapAmount),
            sqrtPriceLimitX96,
            abi.encode(pool)
        );

        // 步骤3: 计算实际获得的 underlyingToken 数量
        uint256 underlyingTokenAfter = IERC20(underlyingToken).balanceOf(address(this));
        uint256 underlyingTokenReceived = underlyingTokenAfter - underlyingTokenBefore;

        // underlyingTokenReceived: swap 实际获得的代币数量。remainingAmount: 剩余的一半 USDT
        uint256 underlyingTokenBalance = underlyingTokenReceived;
        uint256 usdtBalance = remainingAmount;

        // 批准 Position Manager 使用代币
        IERC20(underlyingToken).approve(POSITION_MANAGER, underlyingTokenBalance);
        IERC20(USDT).approve(POSITION_MANAGER, usdtBalance);

        // 根据池子中代币顺序设置 amount0 和 amount1
        uint256 amount0Desired;
        uint256 amount1Desired;
        if (zeroForOne) {
            amount0Desired = usdtBalance;
            amount1Desired = underlyingTokenBalance;
        } else {
            amount0Desired = underlyingTokenBalance;
            amount1Desired = usdtBalance;
        }

        // 构建增加流动性参数
        IV3NonfungiblePositionManager.IncreaseLiquidityParams memory params =
            IV3NonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: (amount0Desired * SLIPPAGE_TOLERANCE) / 100,
                amount1Min: (amount1Desired * SLIPPAGE_TOLERANCE) / 100,
                deadline: block.timestamp + 15 minutes
            });
        // 调用 increaseLiquidity 增加流动性
        (uint128 liquidityAdded, uint256 amount0Used, uint256 amount1Used) =
            IV3NonfungiblePositionManager(POSITION_MANAGER).increaseLiquidity(params);

        emit LiquidityAdded(positionTokenId, liquidityAdded, amount0Used, amount1Used);
    }

    // PancakeSwap V3 Swap 回调函数
    function pancakeV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        require(msg.sender == pool, "Invalid callback caller");

        // 确定需要支付的代币和数量
        if (amount0Delta > 0) {
            address token0 = IPancakeV3Pool(pool).token0();
            IERC20(token0).safeTransfer(msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            address token1 = IPancakeV3Pool(pool).token1();
            IERC20(token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    // ==============internal function================
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
