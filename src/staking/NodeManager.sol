// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    function initialize(address initialOwner, address _underlyingToken, address _distributeRewardAddress) public initializer  {
        __Ownable_init(initialOwner);
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

        nodeRewardTypeInfo[recipient][incomeType] += amount;

        emit DistributeNodeRewards({
            recipient: recipient,
            amount: amount,
            incomeType: incomeType
        });
    }

    // ==============internal function================
    function matchNodeTypeByAmount(uint256 amount) internal view returns (uint8)  {
        uint8 buyNodeType;
        if (amount == buyDistributedNode)  {
            buyNodeType = NodeType.DistributedNode;
        } else if (amount == buyClusterNode) {
            buyNodeType = NodeType.ClusterNode;
        } else  {
            revert InvalidNodeTypeError(amount);
        }
        return nodeType;
    }
}
