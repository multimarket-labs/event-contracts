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

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param initialOwner Initial owner address
     * @param _daoRewardManager DAO reward manager contract address
     * @param _underlyingToken Underlying token address
     * @param _usdt USDT address
     * @param _distributeRewardAddress Reward distribution manager address
     * @param _eventFundingManager Event funding manager contract address
     */
    function initialize(
        address initialOwner,
        address _daoRewardManager,
        address _underlyingToken,
        address _usdt,
        address _distributeRewardAddress,
        address _eventFundingManager
    ) public initializer {
        __Ownable_init(initialOwner);
        daoRewardManager = IDaoRewardManager(_daoRewardManager);
        underlyingToken = _underlyingToken;
        USDT = _usdt;
        distributeRewardAddress = _distributeRewardAddress;
        eventFundingManager = IEventFundingManager(_eventFundingManager);
    }

    /**
     * @dev Set trading pool address
     * @param _pool Pancake V3 trading pool address
     */
    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Invalid pool address");
        pool = _pool;
    }

    /**
     * @dev Set liquidity position NFT ID
     * @param _tokenId NFT Token ID of Pancake V3 liquidity position
     */
    function setPositionTokenId(uint256 _tokenId) external onlyOwner {
        require(_tokenId > 0, "Invalid token ID");
        positionTokenId = _tokenId;
    }

    /**
     * @dev Purchase node - User side
     * @param amount Token amount required to purchase node, must match distributed node or cluster node price
     */
    function purchaseNode(uint256 amount) external {
        if (nodeBuyerInfo[msg.sender].amount > 0) {
            revert HaveAlreadyBuyNode(msg.sender);
        }

        uint8 buyNodeType = matchNodeTypeByAmount(amount);

        IERC20(USDT).safeTransferFrom(msg.sender, address(this), amount);

        NodeBuyerInfo memory buyerInfo = NodeBuyerInfo({buyer: msg.sender, nodeType: buyNodeType, amount: amount});

        nodeBuyerInfo[msg.sender] = buyerInfo;

        emit PurchaseNodes({buyer: msg.sender, amount: amount, nodeType: buyNodeType});
    }

    /**
     * @dev Distribute node rewards (only reward distribution manager can call)
     * @param recipient Address receiving the reward
     * @param amount Reward amount
     * @param incomeType Income type (0 - node income, 1 - promotion income)
     */
    function distributeRewards(address recipient, uint256 amount, uint8 incomeType)
        external
        onlyDistributeRewardManager
    {
        require(recipient != address(0), "NodeManager.distributeRewards: zero address");
        require(amount > 0, "NodeManager.distributeRewards: amount must more than zero");
        require(incomeType <= uint256(NodeIncomeType.PromoteProfit), "Invalid income type");

        nodeRewardTypeInfo[recipient][incomeType].amount += amount;

        emit DistributeNodeRewards({recipient: recipient, amount: amount, incomeType: incomeType});
    }

    /**
     * @dev Claim node rewards - User side
     * @param incomeType Income type (0 - node income, 1 - promotion income)
     * @notice 20% of rewards will be forcibly withheld and converted to USDT for deposit into event prediction market
     */
    function claimReward(uint8 incomeType) external {
        require(incomeType <= uint256(NodeIncomeType.PromoteProfit), "Invalid income type");
        uint256 rewardAmount = nodeRewardTypeInfo[msg.sender][incomeType].amount;
        nodeRewardTypeInfo[msg.sender][incomeType].amount = 0;

        uint256 toEventPredictionAmount = (rewardAmount * 20) / 100;

        if (toEventPredictionAmount > 0) {
            daoRewardManager.withdraw(address(this), toEventPredictionAmount);

            uint256 usdtAmount =
                SwapHelper.swapTokenToUsdt(pool, underlyingToken, USDT, toEventPredictionAmount, address(this));

            IERC20(USDT).approve(address(eventFundingManager), usdtAmount);
            eventFundingManager.depositUsdt(usdtAmount);
        }

        uint256 canWithdrawAmount = rewardAmount - toEventPredictionAmount;
        daoRewardManager.withdraw(msg.sender, canWithdrawAmount);
    }

    /**
     * @dev Add liquidity to Pancake V3 pool (only owner can call)
     * @param amount Total amount of USDT to add
     * @notice Convert 50% of USDT to underlying token, then add liquidity
     */
    function addLiquidity(uint256 amount) external onlyOwner {
        require(pool != address(0), "Pool not set");
        require(amount > 0, "Amount must be greater than 0");
        require(positionTokenId > 0, "Position token not initialized");

        uint256 swapAmount = amount / 2;
        uint256 remainingAmount = amount - swapAmount;
        IERC20(USDT).approve(POSITION_MANAGER, amount);

        uint256 underlyingTokenReceived =
            SwapHelper.swapUsdtToToken(pool, USDT, underlyingToken, swapAmount, address(this));

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
     * @dev Pancake V3 swap callback function
     * @param amount0Delta Change amount of token0
     * @param amount1Delta Change amount of token1
     * @param data Callback data
     */
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        require(msg.sender == pool, "Invalid callback caller");
        SwapHelper.handleSwapCallback(pool, amount0Delta, amount1Delta, msg.sender);
    }

    /**
     * @dev Match node type by amount
     * @param amount Purchase amount
     * @return Node type (0 - distributed node, 1 - cluster node)
     */
    function matchNodeTypeByAmount(uint256 amount) internal view returns (uint8) {
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
