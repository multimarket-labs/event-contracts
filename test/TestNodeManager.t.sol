// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/staking/NodeManager.sol";
import "../src/interfaces/staking/INodeManager.sol";
import "../src/interfaces/token/IDaoRewardManager.sol";
import "../src/token/allocation/DaoRewardManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// forge test --match-contract NodeManagerTest -vvv

// Mock USDT Token
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 10000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock ChooseMeToken with quote functionality
contract MockChooseMeToken is ERC20 {
    uint256 public exchangeRate = 1; // 1:1 by default

    constructor() ERC20("Mock ChooseMe Token", "MCMT") {
        _mint(msg.sender, 10000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address user, uint256 _amount) external {
        _burn(user, _amount);
    }

    function quote(uint256 amount) external view returns (uint256) {
        return amount * exchangeRate;
    }

    function setExchangeRate(uint256 rate) external {
        exchangeRate = rate;
    }
}

// Mock EventFundingManager
contract MockEventFundingManager {
    uint256 public totalDeposited;
    address public lastDepositor;

    function depositUsdt(uint256 amount) external returns (bool) {
        totalDeposited += amount;
        lastDepositor = msg.sender;
        return true;
    }
}

contract TestNodeManager is Test {
    NodeManager public nodeManager;
    DaoRewardManager public daoRewardManager;
    MockUSDT public usdt;
    MockChooseMeToken public chooseMeToken;
    MockEventFundingManager public eventFundingManager;

    address public owner = address(0x01);
    address public distributeRewardAddress = address(0x02);
    address public buyer1 = address(0x03);
    address public buyer2 = address(0x04);
    address public recipient = address(0x05);

    uint256 public constant DISTRIBUTED_NODE_PRICE = 500 * 10 ** 18;
    uint256 public constant CLUSTER_NODE_PRICE = 1000 * 10 ** 18;

    event PurchaseNodes(address indexed buyer, uint256 amount, uint8 nodeType);
    event DistributeNodeRewards(address indexed recipient, uint256 amount, uint8 incomeType);
    event outOfAchieveReturnsNodeExit(address indexed recipient, uint256 totalReward, uint256 blockNumber);
    event LiquidityAdded(uint256 liquidity, uint256 amount0, uint256 amount1);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        usdt = new MockUSDT();
        chooseMeToken = new MockChooseMeToken();
        eventFundingManager = new MockEventFundingManager();

        // Deploy NodeManager with proxy first
        NodeManager logic = new NodeManager();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(logic), owner, "");
        nodeManager = NodeManager(payable(address(proxy)));

        // Deploy DaoRewardManager with proxy (pass NodeManager address)
        DaoRewardManager daoLogic = new DaoRewardManager();
        TransparentUpgradeableProxy daoProxy = new TransparentUpgradeableProxy(address(daoLogic), owner, "");
        daoRewardManager = DaoRewardManager(payable(address(daoProxy)));
        daoRewardManager.initialize(owner, address(chooseMeToken), address(nodeManager), distributeRewardAddress);

        // Initialize NodeManager
        nodeManager.initialize(
            owner,
            address(daoRewardManager),
            address(chooseMeToken),
            address(usdt),
            distributeRewardAddress,
            address(eventFundingManager)
        );

        // Setup tokens for testing
        usdt.mint(buyer1, 10000 * 10 ** 18);
        usdt.mint(buyer2, 10000 * 10 ** 18);
        chooseMeToken.transfer(address(daoRewardManager), 1000000 * 10 ** 18);

        vm.stopPrank();

        // Approve NodeManager to spend USDT
        vm.prank(buyer1);
        usdt.approve(address(nodeManager), type(uint256).max);

        vm.prank(buyer2);
        usdt.approve(address(nodeManager), type(uint256).max);
    }

    // ==================== Initialization Tests ====================

    function testInitialization() public {
        assertEq(nodeManager.owner(), owner, "Owner should be set correctly");
        assertEq(address(nodeManager.daoRewardManager()), address(daoRewardManager), "DaoRewardManager should be set");
        assertEq(nodeManager.underlyingToken(), address(chooseMeToken), "Underlying token should be chooseMeToken");
        assertEq(nodeManager.USDT(), address(usdt), "USDT should be set correctly");
        assertEq(
            nodeManager.distributeRewardAddress(), distributeRewardAddress, "Distribute reward address should be set"
        );
        assertEq(
            address(nodeManager.eventFundingManager()),
            address(eventFundingManager),
            "EventFundingManager should be set"
        );
    }

    function testConstants() public {
        assertEq(nodeManager.buyDistributedNode(), DISTRIBUTED_NODE_PRICE, "Distributed node price should be correct");
        assertEq(nodeManager.buyClusterNode(), CLUSTER_NODE_PRICE, "Cluster node price should be correct");
    }

    // ==================== Purchase Node Tests ====================

    function testPurchaseDistributedNode() public {
        uint256 balanceBefore = usdt.balanceOf(buyer1);

        vm.prank(buyer1);
        vm.expectEmit(true, false, false, true);
        emit PurchaseNodes(buyer1, DISTRIBUTED_NODE_PRICE, 0);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        (address buyer, uint8 nodeType, uint256 amount) = nodeManager.nodeBuyerInfo(buyer1);
        assertEq(buyer, buyer1, "Buyer should be buyer1");
        assertEq(nodeType, 0, "Node type should be DistributedNode");
        assertEq(amount, DISTRIBUTED_NODE_PRICE, "Amount should be distributed node price");
        assertEq(usdt.balanceOf(buyer1), balanceBefore - DISTRIBUTED_NODE_PRICE, "USDT should be transferred");
        assertEq(usdt.balanceOf(address(nodeManager)), DISTRIBUTED_NODE_PRICE, "NodeManager should receive USDT");
    }

    function testPurchaseClusterNode() public {
        uint256 balanceBefore = usdt.balanceOf(buyer1);

        vm.prank(buyer1);
        vm.expectEmit(true, false, false, true);
        emit PurchaseNodes(buyer1, CLUSTER_NODE_PRICE, 1);
        nodeManager.purchaseNode(CLUSTER_NODE_PRICE);

        (address buyer, uint8 nodeType, uint256 amount) = nodeManager.nodeBuyerInfo(buyer1);
        assertEq(buyer, buyer1, "Buyer should be buyer1");
        assertEq(nodeType, 1, "Node type should be ClusterNode");
        assertEq(amount, CLUSTER_NODE_PRICE, "Amount should be cluster node price");
        assertEq(usdt.balanceOf(buyer1), balanceBefore - CLUSTER_NODE_PRICE, "USDT should be transferred");
    }

    function testPurchaseNodeRevertsWithInvalidAmount() public {
        uint256 invalidAmount = 300 * 10 ** 18;

        vm.prank(buyer1);
        vm.expectRevert(abi.encodeWithSelector(INodeManager.InvalidNodeTypeError.selector, invalidAmount));
        nodeManager.purchaseNode(invalidAmount);
    }

    function testPurchaseNodeRevertsIfAlreadyPurchased() public {
        vm.startPrank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        vm.expectRevert(abi.encodeWithSelector(INodeManager.HaveAlreadyBuyNode.selector, buyer1));
        nodeManager.purchaseNode(CLUSTER_NODE_PRICE);
        vm.stopPrank();
    }

    function testMultipleBuyersPurchaseNodes() public {
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        vm.prank(buyer2);
        nodeManager.purchaseNode(CLUSTER_NODE_PRICE);

        (address buyer1Addr, uint8 nodeType1,) = nodeManager.nodeBuyerInfo(buyer1);
        assertEq(buyer1Addr, buyer1, "Buyer1 should be recorded");
        assertEq(nodeType1, 0, "Buyer1 should have DistributedNode");

        (address buyer2Addr, uint8 nodeType2,) = nodeManager.nodeBuyerInfo(buyer2);
        assertEq(buyer2Addr, buyer2, "Buyer2 should be recorded");
        assertEq(nodeType2, 1, "Buyer2 should have ClusterNode");
    }

    // ==================== Distribute Rewards Tests ====================

    function testDistributeRewards() public {
        // First purchase a node
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        uint256 rewardAmount = 100 * 10 ** 18;
        uint8 incomeType = 0; // NodeTypeProfit

        vm.prank(distributeRewardAddress);
        vm.expectEmit(true, false, false, true);
        emit DistributeNodeRewards(buyer1, rewardAmount, incomeType);
        nodeManager.distributeRewards(buyer1, rewardAmount, incomeType);

        (, uint256 amount,) = nodeManager.nodeRewardTypeInfo(buyer1, incomeType);
        assertEq(amount, rewardAmount, "Reward amount should be recorded");

        (uint256 totalReward,,) = nodeManager.rewardClaimInfo(buyer1);
        assertEq(totalReward, rewardAmount, "Total reward should be updated");
    }

    function testDistributeMultipleRewardTypes() public {
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        uint256 rewardAmount1 = 100 * 10 ** 18;
        uint256 rewardAmount2 = 50 * 10 ** 18;

        vm.startPrank(distributeRewardAddress);
        nodeManager.distributeRewards(buyer1, rewardAmount1, 0); // NodeTypeProfit
        nodeManager.distributeRewards(buyer1, rewardAmount2, 1); // TradeFeeProfit
        vm.stopPrank();

        (, uint256 amount1,) = nodeManager.nodeRewardTypeInfo(buyer1, 0);
        (, uint256 amount2,) = nodeManager.nodeRewardTypeInfo(buyer1, 1);
        assertEq(amount1, rewardAmount1, "First reward type should be recorded");
        assertEq(amount2, rewardAmount2, "Second reward type should be recorded");

        (uint256 totalReward,,) = nodeManager.rewardClaimInfo(buyer1);
        assertEq(totalReward, rewardAmount1 + rewardAmount2, "Total reward should be sum of all rewards");
    }

    function testDistributeRewardsRevertsWithZeroAddress() public {
        vm.prank(distributeRewardAddress);
        vm.expectRevert("NodeManager.distributeRewards: zero address");
        nodeManager.distributeRewards(address(0), 100 * 10 ** 18, 0);
    }

    function testDistributeRewardsRevertsWithZeroAmount() public {
        vm.prank(distributeRewardAddress);
        vm.expectRevert("NodeManager.distributeRewards: amount must more than zero");
        nodeManager.distributeRewards(buyer1, 0, 0);
    }

    function testDistributeRewardsRevertsWithInvalidIncomeType() public {
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        vm.prank(distributeRewardAddress);
        vm.expectRevert("Invalid income type");
        nodeManager.distributeRewards(buyer1, 100 * 10 ** 18, 6); // Invalid type
    }

    function testDistributeRewardsRevertsWithUnauthorizedCaller() public {
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        vm.prank(buyer2); // Not distributeRewardAddress
        vm.expectRevert("onlyDistributeRewardManager");
        nodeManager.distributeRewards(buyer1, 100 * 10 ** 18, 0);
    }

    function testDistributeRewardsMarksNodeAsOutOfWhenExceedsThreeTimes() public {
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        // Set exchange rate so reward value exceeds 3x purchase amount
        vm.prank(owner);
        chooseMeToken.setExchangeRate(10);

        // Distribute rewards that will exceed 3x when converted to USDT
        uint256 rewardAmount = (DISTRIBUTED_NODE_PRICE * 3) / 10 + 1;

        vm.prank(distributeRewardAddress);
        vm.expectEmit(true, false, false, true);
        emit outOfAchieveReturnsNodeExit(buyer1, rewardAmount, block.number);
        nodeManager.distributeRewards(buyer1, rewardAmount, 0);

        (,, bool isOutOf) = nodeManager.rewardClaimInfo(buyer1);
        assertTrue(isOutOf, "Node should be marked as out of rewards");
    }

    function testDistributeRewardsRevertsWhenNodeIsOutOf() public {
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        vm.prank(owner);
        chooseMeToken.setExchangeRate(10);

        uint256 rewardAmount = (DISTRIBUTED_NODE_PRICE * 3) / 10 + 1;

        vm.startPrank(distributeRewardAddress);
        nodeManager.distributeRewards(buyer1, rewardAmount, 0);

        vm.expectRevert("Recipient is out of rewards");
        nodeManager.distributeRewards(buyer1, 1 * 10 ** 18, 0);
        vm.stopPrank();
    }

    // ==================== Claim Reward Tests ====================
    // Note: These tests are skipped as they require DEX (PancakeSwap) integration
    // They should be tested in integration tests with proper DEX infrastructure

    function testClaimRewardBasic() public {
        vm.skip(true); // Skip: requires PancakeSwap V2 Router for token swapping

        // Setup: purchase node and distribute rewards
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        uint256 rewardAmount = 100 * 10 ** 18;
        vm.prank(distributeRewardAddress);
        nodeManager.distributeRewards(buyer1, rewardAmount, 0);

        // Claim 50% of rewards
        uint256 claimAmount = 50 * 10 ** 18;
        uint256 expectedToEventPrediction = (claimAmount * 20) / 100; // 20%
        uint256 expectedToBuyer = claimAmount - expectedToEventPrediction; // 80%

        uint256 buyer1BalanceBefore = chooseMeToken.balanceOf(buyer1);

        vm.prank(buyer1);
        nodeManager.claimReward(claimAmount);

        (uint256 totalReward, uint256 claimedReward,) = nodeManager.rewardClaimInfo(buyer1);
        assertEq(claimedReward, claimAmount, "Claimed reward should be recorded");
        assertEq(chooseMeToken.balanceOf(buyer1), buyer1BalanceBefore + expectedToBuyer, "Buyer should receive 80%");
    }

    function testClaimRewardRevertsWhenAmountExceedsAvailable() public {
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        uint256 rewardAmount = 100 * 10 ** 18;
        vm.prank(distributeRewardAddress);
        nodeManager.distributeRewards(buyer1, rewardAmount, 0);

        vm.prank(buyer1);
        vm.expectRevert("Claim amount mismatch");
        nodeManager.claimReward(rewardAmount); // Trying to claim full or more amount should fail
    }

    function testClaimRewardMultipleTimes() public {
        vm.skip(true); // Skip: requires PancakeSwap V2 Router for token swapping

        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        uint256 rewardAmount = 100 * 10 ** 18;
        vm.prank(distributeRewardAddress);
        nodeManager.distributeRewards(buyer1, rewardAmount, 0);

        // Claim in two parts
        uint256 claimAmount1 = 30 * 10 ** 18;
        uint256 claimAmount2 = 20 * 10 ** 18;

        vm.startPrank(buyer1);
        nodeManager.claimReward(claimAmount1);
        nodeManager.claimReward(claimAmount2);
        vm.stopPrank();

        (, uint256 claimedReward,) = nodeManager.rewardClaimInfo(buyer1);
        assertEq(claimedReward, claimAmount1 + claimAmount2, "Total claimed should be sum of both claims");
    }

    // ==================== Owner Function Tests ====================

    function testOnlyOwnerCanCallAddLiquidity() public {
        vm.prank(buyer1);
        vm.expectRevert();
        nodeManager.addLiquidity(1000 * 10 ** 18);
    }

    // ==================== Edge Cases and Security Tests ====================

    function testCannotReinitialize() public {
        vm.prank(owner);
        vm.expectRevert();
        nodeManager.initialize(
            owner,
            address(daoRewardManager),
            address(chooseMeToken),
            address(usdt),
            distributeRewardAddress,
            address(eventFundingManager)
        );
    }

    function testNodePurchaseWithExactAmountRequired() public {
        uint256 balanceBefore = usdt.balanceOf(address(nodeManager));

        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        assertEq(
            usdt.balanceOf(address(nodeManager)) - balanceBefore,
            DISTRIBUTED_NODE_PRICE,
            "Exact amount should be transferred"
        );
    }

    function testRewardClaimInfoTracking() public {
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        vm.prank(distributeRewardAddress);
        nodeManager.distributeRewards(buyer1, 100 * 10 ** 18, 0);

        vm.prank(distributeRewardAddress);
        nodeManager.distributeRewards(buyer1, 50 * 10 ** 18, 1);

        (uint256 totalReward, uint256 claimedReward, bool isOutOf) = nodeManager.rewardClaimInfo(buyer1);
        assertEq(totalReward, 150 * 10 ** 18, "Total reward should accumulate");
        assertEq(claimedReward, 0, "Claimed reward should be 0 initially");
        assertFalse(isOutOf, "Should not be out of rewards");
    }

    function testNodeTypeEnumMapping() public {
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        (, uint8 nodeType,) = nodeManager.nodeBuyerInfo(buyer1);
        assertEq(nodeType, uint8(INodeManager.NodeType.DistributedNode), "Should map to correct enum value");

        vm.prank(buyer2);
        nodeManager.purchaseNode(CLUSTER_NODE_PRICE);

        (, uint8 nodeType2,) = nodeManager.nodeBuyerInfo(buyer2);
        assertEq(nodeType2, uint8(INodeManager.NodeType.ClusterNode), "Should map to correct enum value");
    }

    function testAllIncomeTypes() public {
        vm.prank(buyer1);
        nodeManager.purchaseNode(DISTRIBUTED_NODE_PRICE);

        vm.startPrank(distributeRewardAddress);
        for (uint8 i = 0; i <= uint8(INodeManager.NodeIncomeType.PromoteProfit); i++) {
            nodeManager.distributeRewards(buyer1, 10 * 10 ** 18, i);
        }
        vm.stopPrank();

        (uint256 totalReward,,) = nodeManager.rewardClaimInfo(buyer1);
        assertEq(totalReward, 50 * 10 ** 18, "Should accumulate all income types");
    }
}
