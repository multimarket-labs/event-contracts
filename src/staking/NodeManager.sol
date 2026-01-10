// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/token/IDaoRewardManager.sol";
import "../interfaces/staking/IEventFundingManager.sol";
import "../interfaces/token/IChooseMeToken.sol";
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
     * @dev Purchase node - User side
     * @param amount Token amount required to purchase node, must match distributed node or cluster node price
     */
    function purchaseNode(uint256 amount) external {
        if (nodeBuyerInfo[msg.sender].amount > 0) {
            revert HaveAlreadyBuyNode(msg.sender);
        }
        require(inviters[msg.sender] != address(0), "inviter not set");

        uint8 buyNodeType = matchNodeTypeByAmount(amount);
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), amount);
        NodeBuyerInfo memory buyerInfo = NodeBuyerInfo({buyer: msg.sender, nodeType: buyNodeType, amount: amount});
        nodeBuyerInfo[msg.sender] = buyerInfo;

        emit PurchaseNodes({buyer: msg.sender, amount: amount, nodeType: buyNodeType});
    }

    function bindInviter(address inviter) public {
        require(inviter != address(0), "Inviter cannot be zero address");
        require(inviters[msg.sender] == address(0), "Inviter already set");

        inviters[msg.sender] = inviter;
        emit BindInviter({inviter: inviter, invitee: msg.sender});
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
        require(!rewardClaimInfo[recipient].isOutOf, "Recipient is out of rewards");

        nodeRewardTypeInfo[recipient][incomeType].amount += amount;
        rewardClaimInfo[recipient].totalReward += amount;
        uint256 usdtRewardAmount = IChooseMeToken(underlyingToken).quote(rewardClaimInfo[recipient].totalReward);
        if (usdtRewardAmount > nodeBuyerInfo[recipient].amount * 3) {
            rewardClaimInfo[recipient].isOutOf = true;
            emit outOfAchieveReturnsNodeExit({
                recipient: recipient, totalReward: rewardClaimInfo[recipient].totalReward, blockNumber: block.number
            });
        }
        emit DistributeNodeRewards({recipient: recipient, amount: amount, incomeType: incomeType});
    }

    /**
     * @dev Claim node rewards - User side
     * @param amount reward amount to claim
     * @notice 20% of rewards will be forcibly withheld and converted to USDT for deposit into event prediction market
     */
    function claimReward(uint256 amount) external {
        require(
            amount < rewardClaimInfo[msg.sender].totalReward - rewardClaimInfo[msg.sender].claimedReward,
            "Claim amount mismatch"
        );

        rewardClaimInfo[msg.sender].claimedReward += amount;
        uint256 toEventPredictionAmount = (amount * 20) / 100;

        if (toEventPredictionAmount > 0) {
            daoRewardManager.withdraw(address(this), toEventPredictionAmount);

            uint256 usdtAmount =
                SwapHelper.swapV2(V2_ROUTER, underlyingToken, USDT, toEventPredictionAmount, address(this));
            IERC20(USDT).approve(address(eventFundingManager), usdtAmount);
            eventFundingManager.depositUsdt(usdtAmount);
        }

        uint256 canWithdrawAmount = amount - toEventPredictionAmount;
        daoRewardManager.withdraw(msg.sender, canWithdrawAmount);
    }

    /**
     * @dev Add liquidity to PancakeSwap V2 pool (only owner can call)
     * @param amount Total amount of USDT to add
     * @notice Convert 50% of USDT to underlying token, then add liquidity to V2
     */
    function addLiquidity(uint256 amount) external onlyDistributeRewardManager {
        require(amount > 0, "Amount must be greater than 0");

        (uint256 liquidityAdded, uint256 amount0Used, uint256 amount1Used) =
            SwapHelper.addLiquidityV2(V2_ROUTER, USDT, underlyingToken, amount, address(this));

        emit LiquidityAdded(liquidityAdded, amount0Used, amount1Used);
    }

    /**
     * @dev Match node type by amount
     * @param amount Purchase amount
     * @return Node type (0 - distributed node, 1 - cluster node)
     */
    function matchNodeTypeByAmount(uint256 amount) internal pure returns (uint8) {
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
