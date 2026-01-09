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
        poolType = 1; // default pancake v2 liquidity
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
     * @dev Set pool type for liquidity operations
     * @param _poolType Pool type (1 for PancakeSwap V2, 2 for PancakeSwap V3)
     */
    function setPoolType(uint8 _poolType) external onlyOwner {
        require(_poolType == 1 || _poolType == 2, "Invalid pool type");
        poolType = _poolType;
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
     * @param nodeAmount Node income type reward amount to claim
     * @param promotionAmount Promotion income type reward amount to claim
     * @notice 20% of rewards will be forcibly withheld and converted to USDT for deposit into event prediction market
     */
    function claimReward(uint256 nodeAmount, uint256 promotionAmount) external {
        require(
            nodeAmount == nodeRewardTypeInfo[msg.sender][0].amount
                || promotionAmount == nodeRewardTypeInfo[msg.sender][0].amount,
            "Claim amount mismatch"
        );

        uint256 rewardAmount = nodeRewardTypeInfo[msg.sender][0].amount + nodeRewardTypeInfo[msg.sender][1].amount;
        nodeRewardTypeInfo[msg.sender][0].amount = 0;
        nodeRewardTypeInfo[msg.sender][1].amount = 0;

        require(rewardAmount > 0, "No rewards to claim");

        uint256 toEventPredictionAmount = (rewardAmount * 20) / 100;

        if (toEventPredictionAmount > 0) {
            daoRewardManager.withdraw(address(this), toEventPredictionAmount);

            uint256 usdtAmount;
            if (poolType == 1) {
                usdtAmount = SwapHelper.swapV2(V2_ROUTER, underlyingToken, USDT, toEventPredictionAmount, address(this));
            } else {
                usdtAmount = SwapHelper.swapV3(pool, underlyingToken, USDT, toEventPredictionAmount, address(this));
            }

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

        if (poolType == 1) {
            (uint256 liquidityAdded, uint256 amount0Used, uint256 amount1Used) =
                SwapHelper.addLiquidityV2(V2_ROUTER, USDT, underlyingToken, amount, address(this));

            emit LiquidityAdded(1, 0, liquidityAdded, amount0Used, amount1Used);
        } else {
            (uint256 liquidityAdded, uint256 amount0Used, uint256 amount1Used) = SwapHelper.addLiquidityV3(
                POSITION_MANAGER, pool, positionTokenId, USDT, underlyingToken, amount, SLIPPAGE_TOLERANCE
            );

            emit LiquidityAdded(2, positionTokenId, liquidityAdded, amount0Used, amount1Used);
        }
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
