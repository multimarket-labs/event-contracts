// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/token/IDaoRewardManager.sol";

import { NodeManagerStorage } from "./NodeManagerStorage.sol";

contract NodeManager is Initializable, OwnableUpgradeable, PausableUpgradeable, NodeManagerStorage  {
    using SafeERC20 for IERC20;

    modifier onlyDistributeRewardManager() {
        require(msg.sender == address(distributeRewardAddress), "onlyDistributeRewardManager");
        _;
    }

    constructor(){
        _disableInitializers();
    }

    function initialize(address initialOwner, IDaoRewardManager _daoRewardManager, address _underlyingToken, address _distributeRewardAddress) public initializer  {
        __Ownable_init(initialOwner);
        daoRewardManager = _daoRewardManager;
        underlyingToken = _underlyingToken;
        distributeRewardAddress = _distributeRewardAddress;
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

    function addLiquidity() external {
        // todo: 将所有购买节点的资金用于加 LP
    }

    // ==============internal function================
    function matchNodeTypeByAmount(uint256 amount) internal view returns (uint8)  {
        uint8 buyNodeType;
        if (amount == buyDistributedNode)  {
            buyNodeType = uint8(NodeType.DistributedNode);
        } else if (amount == buyClusterNode) {
            buyNodeType = uint8(NodeType.ClusterNode);
        } else  {
            revert InvalidNodeTypeError(amount);
        }
        return buyNodeType;
    }
}
