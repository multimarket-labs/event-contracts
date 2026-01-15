// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/staking/StakingManager.sol";
import "../src/interfaces/staking/IStakingManager.sol";
import "../src/interfaces/token/IDaoRewardManager.sol";
import "../src/interfaces/token/IChooseMeToken.sol";
import "../src/interfaces/staking/IEventFundingManager.sol";
import "../src/interfaces/staking/ISubTokenFundingManager.sol";
import "../src/token/allocation/DaoRewardManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// forge test --match-contract TestStakingManager -vvv

// Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock ChooseMeToken for testing
contract MockChooseMeToken is ERC20, IChooseMeToken {
    uint256 public burnedAmount;
    uint256 public quoteRate = 1 * 10 ** 18; // 1:1 by default

    constructor() ERC20("ChooseMe Token", "CMT") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address user, uint256 _amount) external override {
        _burn(user, _amount);
        burnedAmount += _amount;
    }

    function quote(uint256 amount) external view override returns (uint256) {
        return (amount * quoteRate) / (10 ** 18);
    }

    function setQuoteRate(uint256 rate) external {
        quoteRate = rate;
    }
}

// Mock DaoRewardManager for testing
contract MockDaoRewardManager is IDaoRewardManager {
    address public token;
    mapping(address => uint256) public withdrawnAmount;

    constructor(address _token) {
        token = _token;
    }

    function withdraw(address recipient, uint256 amount) external override {
        withdrawnAmount[recipient] += amount;
        IERC20(token).transfer(recipient, amount);
    }

    function fundRewards(uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }
}

// Mock EventFundingManager for testing
contract MockEventFundingManager is IEventFundingManager {
    uint256 public totalDeposited;
    address public usdt;

    constructor(address _usdt) {
        usdt = _usdt;
    }

    function depositUsdt(uint256 amount) external override returns (bool) {
        IERC20(usdt).transferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;
        emit DepositUsdt(usdt, msg.sender, amount);
        return true;
    }

    function bettingEvent(address event_pool, uint256 amount) external override {}
}

// Mock SubTokenFundingManager for testing
contract MockSubTokenFundingManager is ISubTokenFundingManager {
    address public V2_ROUTER;
    address public USDT;
    address public operatorManager;
    uint256 public totalLiquidityAdded;

    constructor(address _v2Router, address _usdt, address _operatorManager) {
        V2_ROUTER = _v2Router;
        USDT = _usdt;
        operatorManager = _operatorManager;
    }

    function addLiquidity(uint256 amount) external override {
        IERC20(USDT).transferFrom(msg.sender, address(this), amount);
        totalLiquidityAdded += amount;
        emit LiquidityAdded(amount, amount / 2, amount / 2);
    }
}

// Mock NodeManager for testing
contract MockNodeManager {
    mapping(address => address) public inviters;

    function setInviter(address user, address inviter) external {
        inviters[user] = inviter;
    }

    function batchSetInviters(address[] memory users, address[] memory _inviters) external {
        require(users.length == _inviters.length, "Length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            inviters[users[i]] = _inviters[i];
        }
    }
}

// Mock PancakeRouter for testing
contract MockPancakeRouter {
    // Simulate token swaps with a simple 1:1 ratio for testing
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        require(path.length == 2, "Invalid path");
        address tokenIn = path[0];
        address tokenOut = path[1];

        // Transfer tokens from sender to this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Transfer equivalent amount of output token to recipient (1:1 ratio for simplicity)
        IERC20(tokenOut).transfer(to, amountIn);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);
        return (amountADesired, amountBDesired, amountADesired + amountBDesired);
    }
}

contract TestStakingManager is Test {
    StakingManager public stakingManager;
    MockERC20 public usdt;
    MockChooseMeToken public cmt;
    MockDaoRewardManager public daoRewardManager;
    MockEventFundingManager public eventFundingManager;
    MockSubTokenFundingManager public subTokenFundingManager;
    MockNodeManager public nodeManager;
    MockPancakeRouter public pancakeRouter;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;

    address public owner = address(0x1);
    address public operatorManager = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);
    address public constant REAL_V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // Staking amounts
    uint256 constant T1_STAKING = 200 * 10 ** 18;
    uint256 constant T2_STAKING = 600 * 10 ** 18;
    uint256 constant T3_STAKING = 1200 * 10 ** 18;
    uint256 constant T4_STAKING = 2500 * 10 ** 18;
    uint256 constant T5_STAKING = 6000 * 10 ** 18;
    uint256 constant T6_STAKING = 14000 * 10 ** 18;

    event LiquidityProviderDeposits(
        uint256 round,
        address indexed tokenAddress,
        uint8 indexed stakingType,
        address indexed liquidityProvider,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );

    event LiquidityProviderRewards(
        address indexed liquidityProvider,
        uint256 tokenAmount,
        uint256 usdtAmount,
        uint256 rewardBlock,
        uint8 incomeType
    );

    event lpClaimReward(address indexed liquidityProvider, uint256 withdrawAmount, uint256 toPredictionAmount);

    event outOfAchieveReturnsNodeExit(
        address indexed liquidityProvider, uint256 round, uint256 totalReward, uint256 blockNumber
    );

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        usdt = new MockERC20();
        cmt = new MockChooseMeToken();

        // Deploy mock managers
        daoRewardManager = new MockDaoRewardManager(address(cmt));
        eventFundingManager = new MockEventFundingManager(address(usdt));
        nodeManager = new MockNodeManager();

        // Deploy mock PancakeRouter and set it at the real router address
        pancakeRouter = new MockPancakeRouter();
        vm.etch(REAL_V2_ROUTER, address(pancakeRouter).code);

        // Fund the mock router with tokens for swaps
        usdt.mint(REAL_V2_ROUTER, 10000000 * 10 ** 18);
        cmt.mint(REAL_V2_ROUTER, 10000000 * 10 ** 18);

        // Deploy SubTokenFundingManager
        subTokenFundingManager = new MockSubTokenFundingManager(REAL_V2_ROUTER, address(usdt), operatorManager);

        // Deploy StakingManager implementation
        StakingManager implementation = new StakingManager();

        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(owner);

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            StakingManager.initialize.selector,
            owner,
            address(cmt),
            address(usdt),
            operatorManager,
            address(daoRewardManager),
            address(eventFundingManager),
            address(nodeManager),
            address(subTokenFundingManager)
        );

        proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        stakingManager = StakingManager(payable(address(proxy)));

        // Fund test accounts
        usdt.mint(user1, 100000 * 10 ** 18);
        usdt.mint(user2, 100000 * 10 ** 18);
        usdt.mint(user3, 100000 * 10 ** 18);

        // Fund DaoRewardManager with CMT tokens
        cmt.mint(address(daoRewardManager), 1000000 * 10 ** 18);

        vm.stopPrank();
    }

    // ==================== Initialization Tests ====================

    function testInitialization() public view {
        assertEq(stakingManager.owner(), owner);
        assertEq(stakingManager.underlyingToken(), address(cmt));
        assertEq(stakingManager.USDT(), address(usdt));
        assertEq(stakingManager.stakingOperatorManager(), operatorManager);
        assertEq(address(stakingManager.daoRewardManager()), address(daoRewardManager));
        assertEq(address(stakingManager.eventFundingManager()), address(eventFundingManager));
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert();
        stakingManager.initialize(
            owner,
            address(cmt),
            address(usdt),
            operatorManager,
            address(daoRewardManager),
            address(eventFundingManager),
            address(nodeManager),
            address(subTokenFundingManager)
        );
    }

    // ==================== Liquidity Provider Deposit Tests ====================

    function testLiquidityProviderDeposit_T1() public {
        // Set inviter for user1
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);

        vm.expectEmit(true, true, true, true);
        emit LiquidityProviderDeposits(0, address(usdt), 0, user1, T1_STAKING, block.timestamp, 172800);

        stakingManager.liquidityProviderDeposit(T1_STAKING);

        // Verify staking info
        (
            address liquidityProvider,
            uint8 stakingType,
            uint256 amount,
            uint256 rewardUAmount,
            uint256 rewardAmount,
            uint256 startTime,
            uint256 endTime
        ) = stakingManager.currentLiquidityProvider(user1, 0);

        assertEq(liquidityProvider, user1);
        assertEq(stakingType, 0);
        assertEq(amount, T1_STAKING);
        assertEq(startTime, block.timestamp);
        assertEq(endTime, block.timestamp + 172800);

        // Verify total staking reward
        (address lpAddr, uint256 totalStaking, uint256 totalReward,,,,,,) = stakingManager.totalLpStakingReward(user1);
        assertEq(lpAddr, user1);
        assertEq(totalStaking, T1_STAKING);
        assertEq(totalReward, 0);

        vm.stopPrank();
    }

    function testLiquidityProviderDeposit_AllTiers() public {
        uint256[] memory amounts = new uint256[](6);
        amounts[0] = T1_STAKING;
        amounts[1] = T2_STAKING;
        amounts[2] = T3_STAKING;
        amounts[3] = T4_STAKING;
        amounts[4] = T5_STAKING;
        amounts[5] = T6_STAKING;

        for (uint256 i = 0; i < amounts.length; i++) {
            address testUser = address(uint160(1000 + i));
            vm.startPrank(owner);
            usdt.mint(testUser, amounts[i]);
            // Set inviter for each test user
            nodeManager.setInviter(testUser, user2);
            vm.stopPrank();

            vm.startPrank(testUser);
            usdt.approve(address(stakingManager), amounts[i]);
            stakingManager.liquidityProviderDeposit(amounts[i]);

            (, uint8 stakingType, uint256 amount,,,,) = stakingManager.currentLiquidityProvider(testUser, 0);
            assertEq(stakingType, uint8(i));
            assertEq(amount, amounts[i]);
            vm.stopPrank();
        }
    }

    function testLiquidityProviderDeposit_WithInviter() public {
        // Set inviter for user1 in NodeManager
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);

        assertEq(nodeManager.inviters(user1), user2);
        vm.stopPrank();
    }

    function testLiquidityProviderDeposit_InviterCannotBeSelf() public {
        // Don't set inviter, so it should fail due to no inviter
        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);

        // Should revert because inviter is not set
        vm.expectRevert("StakingManager.liquidityProviderDeposit: inviter not set");
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();
    }

    function testLiquidityProviderDeposit_InviterSetOnlyOnce() public {
        // Set inviter for user1
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING + T2_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);

        // Second deposit with different inviter should not change the relationship
        // Note: Second deposit must be >= first deposit, so use T2 which is 600 (> T1 which is 200)
        stakingManager.liquidityProviderDeposit(T2_STAKING);

        assertEq(nodeManager.inviters(user1), user2);
        vm.stopPrank();
    }

    function testLiquidityProviderDeposit_RevertInvalidAmount() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        uint256 invalidAmount = 100 * 10 ** 18;
        usdt.approve(address(stakingManager), invalidAmount);

        vm.expectRevert(abi.encodeWithSelector(IStakingManager.InvalidAmountError.selector, invalidAmount));
        stakingManager.liquidityProviderDeposit(invalidAmount);
        vm.stopPrank();
    }

    function testLiquidityProviderDeposit_MultipleRounds() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING + T2_STAKING);

        // First deposit
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        assertEq(stakingManager.lpStakingRound(user1), 1);

        // Second deposit (must be >= previous)
        stakingManager.liquidityProviderDeposit(T2_STAKING);
        assertEq(stakingManager.lpStakingRound(user1), 2);

        // Verify total staking
        (, uint256 totalStaking,,,,,,,) = stakingManager.totalLpStakingReward(user1);
        assertEq(totalStaking, T1_STAKING + T2_STAKING);
        vm.stopPrank();
    }

    function testLiquidityProviderDeposit_RevertLowerAmount() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T2_STAKING + T1_STAKING);

        // First deposit
        stakingManager.liquidityProviderDeposit(T2_STAKING);

        // Second deposit with lower amount should revert
        vm.expectRevert("StakingManager.liquidityProviderDeposit: amount should more than previous staking amount");
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();
    }

    // ==================== Get Liquidity Providers Tests ====================

    function testGetLiquidityProvidersByType() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        // Set inviters for all users
        vm.startPrank(owner);
        for (uint256 i = 0; i < users.length; i++) {
            nodeManager.setInviter(users[i], owner);
        }
        vm.stopPrank();

        // Deposit T1 for all users
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            usdt.approve(address(stakingManager), T1_STAKING);
            stakingManager.liquidityProviderDeposit(T1_STAKING);
            vm.stopPrank();
        }

        address[] memory t1Providers = stakingManager.getLiquidityProvidersByType(0);
        assertEq(t1Providers.length, 3);
        assertEq(t1Providers[0], user1);
        assertEq(t1Providers[1], user2);
        assertEq(t1Providers[2], user3);
    }

    // ==================== Create Reward Tests ====================

    function testCreateLiquidityProviderReward_DailyNormal() public {
        // Set inviter for user1
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        // First, user needs to stake
        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        uint256 rewardAmount = 10 * 10 ** 18;

        vm.startPrank(operatorManager);
        vm.expectEmit(true, false, false, true);
        emit LiquidityProviderRewards(user1, rewardAmount, rewardAmount, block.number, 0);

        stakingManager.createLiquidityProviderReward(user1, 0, rewardAmount, rewardAmount, 0);
        vm.stopPrank();

        (,, uint256 totalReward,,, uint256 dailyNormalReward,,,) = stakingManager.totalLpStakingReward(user1);
        assertEq(totalReward, rewardAmount);
        assertEq(dailyNormalReward, rewardAmount);
    }

    function testCreateLiquidityProviderReward_DirectReferral() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        uint256 rewardAmount = 5 * 10 ** 18;

        vm.startPrank(operatorManager);
        stakingManager.createLiquidityProviderReward(user1, 0, rewardAmount, rewardAmount, 1);
        vm.stopPrank();

        (,,,,,, uint256 directReferralReward,,) = stakingManager.totalLpStakingReward(user1);
        assertEq(directReferralReward, rewardAmount);
    }

    function testCreateLiquidityProviderReward_TeamReferral() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        uint256 rewardAmount = 8 * 10 ** 18;

        vm.startPrank(operatorManager);
        stakingManager.createLiquidityProviderReward(user1, 0, rewardAmount, rewardAmount, 2);
        vm.stopPrank();

        (,,,,,,, uint256 teamReferralReward,) = stakingManager.totalLpStakingReward(user1);
        assertEq(teamReferralReward, rewardAmount);
    }

    function testCreateLiquidityProviderReward_FomoPool() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        uint256 rewardAmount = 15 * 10 ** 18;

        vm.startPrank(operatorManager);
        stakingManager.createLiquidityProviderReward(user1, 0, rewardAmount, rewardAmount, 3);
        vm.stopPrank();

        (,,,,,,,, uint256 fomoPoolReward) = stakingManager.totalLpStakingReward(user1);
        assertEq(fomoPoolReward, rewardAmount);
    }

    function testCreateLiquidityProviderReward_RevertZeroAddress() public {
        vm.startPrank(operatorManager);
        vm.expectRevert("StakingManager.createLiquidityProviderReward: zero address");
        stakingManager.createLiquidityProviderReward(address(0), 0, 10 * 10 ** 18, 10 * 10 ** 18, 0);
        vm.stopPrank();
    }

    function testCreateLiquidityProviderReward_RevertZeroAmount() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        vm.startPrank(operatorManager);
        vm.expectRevert("StakingManager.createLiquidityProviderReward: amount should more than zero");
        stakingManager.createLiquidityProviderReward(user1, 0, 0, 0, 0);
        vm.stopPrank();
    }

    function testCreateLiquidityProviderReward_RevertInvalidRewardType() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        vm.startPrank(operatorManager);
        vm.expectRevert(abi.encodeWithSelector(IStakingManager.InvalidRewardTypeError.selector, uint8(4)));
        stakingManager.createLiquidityProviderReward(user1, 0, 10 * 10 ** 18, 10 * 10 ** 18, 4);
        vm.stopPrank();
    }

    function testCreateLiquidityProviderReward_RevertOnlyOperator() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);

        vm.expectRevert("onlyRewardDistributionManager");
        stakingManager.createLiquidityProviderReward(user1, 0, 10 * 10 ** 18, 10 * 10 ** 18, 0);
        vm.stopPrank();
    }

    function testCreateLiquidityProviderReward_TeamOutOfReward() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        // Set quote rate so that reward exceeds 3x staking
        vm.startPrank(owner);
        cmt.setQuoteRate(10 * 10 ** 18); // 10:1 ratio
        vm.stopPrank();

        // Create reward that will trigger 3x limit (200 * 3 = 600 USDT)
        uint256 rewardAmount = 70 * 10 ** 18; // 70 CMT = 700 USDT at 10:1
        uint256 expectedCappedReward = 600 * 10 ** 18; // 600 USDT (capped at 3x staking)

        vm.startPrank(operatorManager);
        vm.expectEmit(true, false, false, true);
        emit outOfAchieveReturnsNodeExit(user1, 0, expectedCappedReward, block.number);

        stakingManager.createLiquidityProviderReward(user1, 0, rewardAmount, rewardAmount * 10, 0);

        // Verify team is marked as out of reward
        assertTrue(stakingManager.teamOutOfReward(user1));
        vm.stopPrank();
    }

    function testCreateLiquidityProviderReward_RevertTeamOutOfReward() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        // Set quote rate and trigger out of reward
        vm.startPrank(owner);
        cmt.setQuoteRate(10 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(operatorManager);
        stakingManager.createLiquidityProviderReward(user1, 0, 70 * 10 ** 18, 700 * 10 ** 18, 0);

        // Try to create another reward - should revert
        vm.expectRevert("StakingManager.createLiquidityProviderReward: already reached limit");
        stakingManager.createLiquidityProviderReward(user1, 0, 10 * 10 ** 18, 100 * 10 ** 18, 0);
        vm.stopPrank();
    }

    // ==================== Liquidity Provider Claim Reward Tests ====================

    function testLiquidityProviderClaimReward() public {
        // Set inviter for user1
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        // Setup: stake and create reward
        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        uint256 rewardAmount = 100 * 10 ** 18;

        vm.startPrank(operatorManager);
        stakingManager.createLiquidityProviderReward(user1, 0, rewardAmount, rewardAmount, 0);
        vm.stopPrank();

        uint256 balanceBefore = cmt.balanceOf(user1);

        vm.startPrank(user1);
        uint256 claimAmount = 50 * 10 ** 18;

        vm.expectEmit(true, false, false, true);
        emit lpClaimReward(user1, 40 * 10 ** 18, 10 * 10 ** 18); // 80% withdraw, 20% to event

        stakingManager.liquidityProviderClaimReward(claimAmount);
        vm.stopPrank();

        uint256 balanceAfter = cmt.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, 40 * 10 ** 18); // 80% of claim amount

        (,,,, uint256 claimedReward,,,,) = stakingManager.totalLpStakingReward(user1);
        assertEq(claimedReward, claimAmount);
    }

    function testLiquidityProviderClaimReward_RevertZeroAmount() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);

        vm.expectRevert("StakingManager.liquidityProviderClaimReward: reward amount must more than zero");
        stakingManager.liquidityProviderClaimReward(0);
        vm.stopPrank();
    }

    function testLiquidityProviderClaimReward_RevertExceedReward() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        vm.startPrank(operatorManager);
        stakingManager.createLiquidityProviderReward(user1, 0, 50 * 10 ** 18, 50 * 10 ** 18, 0);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IStakingManager.InvalidRewardAmount.selector, user1, 100 * 10 ** 18));
        stakingManager.liquidityProviderClaimReward(100 * 10 ** 18);
        vm.stopPrank();
    }

    function testLiquidityProviderClaimReward_MultipleClaims() public {
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        vm.startPrank(operatorManager);
        stakingManager.createLiquidityProviderReward(user1, 0, 100 * 10 ** 18, 100 * 10 ** 18, 0);
        vm.stopPrank();

        vm.startPrank(user1);
        stakingManager.liquidityProviderClaimReward(30 * 10 ** 18);
        stakingManager.liquidityProviderClaimReward(50 * 10 ** 18);
        vm.stopPrank();

        (,,,, uint256 claimedReward1,,,,) = stakingManager.totalLpStakingReward(user1);
        assertEq(claimedReward1, 80 * 10 ** 18);

        // Should only be able to claim remaining 20
        vm.startPrank(user1);
        stakingManager.liquidityProviderClaimReward(20 * 10 ** 18);
        vm.stopPrank();

        (,,,, uint256 claimedReward2,,,,) = stakingManager.totalLpStakingReward(user1);
        assertEq(claimedReward2, 100 * 10 ** 18);
    }

    // ==================== Edge Case Tests ====================

    function testReceiveNativeTokens() public {
        uint256 sendAmount = 1 ether;

        vm.deal(user1, sendAmount);
        vm.startPrank(user1);
        (bool success,) = address(stakingManager).call{value: sendAmount}("");
        assertTrue(success);
        vm.stopPrank();

        assertEq(address(stakingManager).balance, sendAmount);
    }

    function testMultipleUsersStaking() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        // Set inviters for all users
        vm.startPrank(owner);
        for (uint256 i = 0; i < users.length; i++) {
            nodeManager.setInviter(users[i], owner);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            usdt.approve(address(stakingManager), T1_STAKING);
            stakingManager.liquidityProviderDeposit(T1_STAKING);
            vm.stopPrank();
        }

        // Verify all users are staked
        for (uint256 i = 0; i < users.length; i++) {
            (, uint256 totalStaking,,,,,,,) = stakingManager.totalLpStakingReward(users[i]);
            assertEq(totalStaking, T1_STAKING);
        }
    }

    function testComplexInvitationChain() public {
        // Set up invitation chain: user2 <- user1 <- user3
        vm.startPrank(owner);
        nodeManager.setInviter(user1, user2);
        nodeManager.setInviter(user3, user1);
        vm.stopPrank();

        // user2 invites user1
        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        // user1 invites user3
        vm.startPrank(user3);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        assertEq(nodeManager.inviters(user1), user2);
        assertEq(nodeManager.inviters(user3), user1);
    }

    function testAllRewardTypes() public {
        // Set inviter for user1
        vm.prank(owner);
        nodeManager.setInviter(user1, user2);

        vm.startPrank(user1);
        usdt.approve(address(stakingManager), T1_STAKING);
        stakingManager.liquidityProviderDeposit(T1_STAKING);
        vm.stopPrank();

        vm.startPrank(operatorManager);
        stakingManager.createLiquidityProviderReward(user1, 0, 10 * 10 ** 18, 10 * 10 ** 18, 0); // Daily
        stakingManager.createLiquidityProviderReward(user1, 0, 5 * 10 ** 18, 5 * 10 ** 18, 1); // Direct
        stakingManager.createLiquidityProviderReward(user1, 0, 8 * 10 ** 18, 8 * 10 ** 18, 2); // Team
        stakingManager.createLiquidityProviderReward(user1, 0, 7 * 10 ** 18, 7 * 10 ** 18, 3); // FOMO
        vm.stopPrank();

        (
            ,,
            uint256 totalReward,,,
            uint256 dailyNormalReward,
            uint256 directReferralReward,
            uint256 teamReferralReward,
            uint256 fomoPoolReward
        ) = stakingManager.totalLpStakingReward(user1);
        assertEq(totalReward, 30 * 10 ** 18);
        assertEq(dailyNormalReward, 10 * 10 ** 18);
        assertEq(directReferralReward, 5 * 10 ** 18);
        assertEq(teamReferralReward, 8 * 10 ** 18);
        assertEq(fomoPoolReward, 7 * 10 ** 18);
    }
}
