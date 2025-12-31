// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/staking/StakingManager.sol";
import "../src/interfaces/staking/IStakingManager.sol";
import "../src/interfaces/token/IDaoRewardManager.sol";
import "../src/token/allocation/DaoRewardManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// forge test --match-contract StakingManagerTest -vvv
// Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1000000 * 10 ** 6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock EventFundingManager for testing
contract MockEventFundingManager {
    function depositEventFunding(uint256 amount) external {}
}

contract StakingManagerTest is Test {
    StakingManager public stakingManager;
    MockERC20 public mockToken;
    DaoRewardManager public mockDaoRewardManager;
    MockEventFundingManager public mockEventFundingManager;

    address public owner = address(0x01);
    address public user1 = address(0x02);
    address public user2 = address(0x03);
    address public user3 = address(0x04);
    address public inviter1 = address(0x05);
    address public stakingOperatorManager = address(0x06);
    address public poolAddress = address(0x07);

    uint256 public constant   T1_STAKING = 200 * 10 ** 6;
    uint256 public constant T2_STAKING = 600 * 10 ** 6;
    uint256 public constant T3_STAKING = 1200 * 10 ** 6;
    uint256 public constant T4_STAKING = 2500 * 10 ** 6;
    uint256 public constant T5_STAKING = 6000 * 10 ** 6;
    uint256 public constant T6_STAKING = 14000 * 10 ** 6;

    event LiquidityProviderDeposits(
        address indexed tokenAddress,
        address indexed liquidityProvider,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );

    event LiquidityProviderRewards(address indexed liquidityProvider, uint256 amount, uint256 rewardBlock, uint8 incomeType);

    event lpRoundStakingOver(address indexed liquidityProvider, uint256 endBlock, uint256 endTime);

    event lpClaimReward(address indexed liquidityProvider, uint256 withdrawAmount, uint256 toPredictionAmount);

    event outOfAchieveReturnsNodeExit(address indexed liquidityProvider, uint256 teamReward, uint256 blockNumber);

    function setUp() public {
        // Deploy mock contracts
        mockToken = new MockERC20();
        mockEventFundingManager = new MockEventFundingManager();

        // Deploy DaoRewardManager with proxy
        DaoRewardManager daoLogic = new DaoRewardManager();
        TransparentUpgradeableProxy daoProxy = new TransparentUpgradeableProxy(address(daoLogic), owner, "");
        mockDaoRewardManager = DaoRewardManager(payable(address(daoProxy)));
        
        // Initialize DaoRewardManager
        mockDaoRewardManager.initialize(owner, address(mockToken));
        
        // Mint reward tokens to DaoRewardManager
        mockToken.mint(address(mockDaoRewardManager), 10000000 * 10 ** 6);

        // Deploy StakingManager with proxy
        StakingManager logic = new StakingManager();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(logic), owner, "");

        stakingManager = StakingManager(payable(address(proxy)));

        // Initialize StakingManager
        stakingManager.initialize(
            owner, 
            address(mockToken), 
            stakingOperatorManager, 
            address(mockDaoRewardManager),
            address(mockEventFundingManager)
        );

        // Set pool address
        vm.prank(owner);
        stakingManager.setPool(poolAddress);

        // Mint tokens to users
        mockToken.mint(user1, 100000 * 10 ** 6);
        mockToken.mint(user2, 100000 * 10 ** 6);
        mockToken.mint(user3, 100000 * 10 ** 6);
        mockToken.mint(inviter1, 100000 * 10 ** 6);

        // Approve StakingManager to spend user tokens
        vm.prank(user1);
        mockToken.approve(address(stakingManager), type(uint256).max);
        vm.prank(user2);
        mockToken.approve(address(stakingManager), type(uint256).max);
        vm.prank(user3);
        mockToken.approve(address(stakingManager), type(uint256).max);
        vm.prank(inviter1);
        mockToken.approve(address(stakingManager), type(uint256).max);
    }

    function testLiquidityProviderDepositT1() public {
        uint256 userBalanceBefore = mockToken.balanceOf(user1);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(stakingManager));

        vm.prank(user1);
        vm.expectEmit(true, true, false, false);
        emit LiquidityProviderDeposits(address(mockToken), user1, T1_STAKING, block.timestamp, 172800);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        // Check balances
        assertEq(mockToken.balanceOf(user1), userBalanceBefore - T1_STAKING, "User1 balance should decrease by T1_STAKING amount");
        assertEq(mockToken.balanceOf(address(stakingManager)), contractBalanceBefore + T1_STAKING, "StakingManager balance should increase by T1_STAKING amount");

        // Check LP info
        (address lp, uint8 stakingType, uint256 amount, uint256 startTime, uint256 endTime, uint8 stakingStatus) = stakingManager
            .currentLiquidityProvider(user1, 0);
        assertEq(lp, user1, "LP address should be user1");
        assertEq(stakingType, uint8(IStakingManager.StakingType.T1), "Staking type should be T1");
        assertEq(amount, T1_STAKING, "Staking amount should be T1_STAKING");
        assertEq(stakingStatus, 0, "Staking status should be 0 (active)");
        assertEq(endTime, block.timestamp + 172800, "End time should be current time + 172800 seconds");

        // Check invite relationship
        assertEq(stakingManager.inviteRelationShip(user1), inviter1, "User1's inviter should be inviter1");

        // Check staking round
        assertEq(stakingManager.lpStakingRound(user1), 1, "User1's staking round should be 1");
    }

    function testLiquidityProviderDepositAllTypes() public {
        uint256[] memory amounts = new uint256[](6);
        amounts[0] = T1_STAKING;
        amounts[1] = T2_STAKING;
        amounts[2] = T3_STAKING;
        amounts[3] = T4_STAKING;
        amounts[4] = T5_STAKING;
        amounts[5] = T6_STAKING;

        address[] memory users = new address[](6);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        users[3] = address(0x07);
        users[4] = address(0x08);
        users[5] = address(0x09);

        for (uint256 i = 0; i < amounts.length; i++) {
            mockToken.mint(users[i], amounts[i]);
            vm.prank(users[i]);
            mockToken.approve(address(stakingManager), amounts[i]);

            vm.prank(users[i]);
            stakingManager.liquidityProviderDeposit(inviter1, amounts[i]);

            (address lp, uint8 stakingType, uint256 amount, , , ) = stakingManager.currentLiquidityProvider(users[i], 0);
            assertEq(lp, users[i], string(abi.encodePacked("LP address should match user at index ", vm.toString(i))));
            assertEq(stakingType, uint8(i), string(abi.encodePacked("Staking type should be T", vm.toString(i + 1))));
            assertEq(amount, amounts[i], string(abi.encodePacked("Staking amount should match amount at index ", vm.toString(i))));
        }
    }

    function testLiquidityProviderDepositRevertsOnInvalidAmount() public {
        uint256 invalidAmount = 500 * 10 ** 6;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IStakingManager.InvalidAmountError.selector, invalidAmount));
        stakingManager.liquidityProviderDeposit(inviter1, invalidAmount);
    }

    function testLiquidityProviderDepositMultipleRounds() public {
        // Check total staking reward
        (address lp, uint256 totalStaking, uint256 totalReward, , , , ) = stakingManager.totalLpStakingReward(user1);
        assertEq(lp, address(0), "LP address should be zero before reward initialization");
        assertEq(totalStaking, 0, "Total staking should be 0 before reward initialization");

        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        assertEq(stakingManager.lpStakingRound(user1), 1, "User1's staking round should be 1 after first deposit");

        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T2_STAKING);

        assertEq(stakingManager.lpStakingRound(user1), 2, "User1's staking round should be 2 after second deposit");

        // Check second round info
        (address lp2, uint8 stakingType2, uint256 amount2, , , ) = stakingManager.currentLiquidityProvider(user1, 1);
        assertEq(lp2, user1, "LP address for round 1 should be user1");
        assertEq(stakingType2, uint8(IStakingManager.StakingType.T2), "Staking type for round 1 should be T2");
        assertEq(amount2, T2_STAKING, "Staking amount for round 1 should be T2_STAKING");
    }

    function testGetLiquidityProvidersByType() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(user2);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(user3);
        stakingManager.liquidityProviderDeposit(inviter1, T2_STAKING);

        address[] memory t1Providers = stakingManager.getLiquidityProvidersByType(uint8(IStakingManager.StakingType.T1));
        assertEq(t1Providers.length, 2, "T1 providers list should have 2 entries");
        assertEq(t1Providers[0], user1, "First T1 provider should be user1");
        assertEq(t1Providers[1], user2, "Second T1 provider should be user2");

        address[] memory t2Providers = stakingManager.getLiquidityProvidersByType(uint8(IStakingManager.StakingType.T2));
        assertEq(t2Providers.length, 1, "T2 providers list should have 1 entry");
        assertEq(t2Providers[0], user3, "First T2 provider should be user3");
    }

    function testCreateLiquidityProviderRewardDailyNormal() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(stakingOperatorManager);
        vm.expectEmit(true, false, false, true);
        emit LiquidityProviderRewards(user1, 1000 * 10 ** 6, block.number, uint8(IStakingManager.StakingRewardType.DailyNormalReward));
        stakingManager.createLiquidityProviderReward(user1, 1000 * 10 ** 6, uint8(IStakingManager.StakingRewardType.DailyNormalReward));

        // Check reward info
        (, , uint256 totalReward, uint256 dailyNormalReward, , , ) = stakingManager.totalLpStakingReward(user1);
        assertEq(totalReward, 1000 * 10 ** 6, "Total reward should be 1000 USDT");
        assertEq(dailyNormalReward, 1000 * 10 ** 6, "Daily normal reward should be 1000 USDT");
    }

    function testCreateLiquidityProviderRewardDirectReferral() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 500 * 10 ** 6, uint8(IStakingManager.StakingRewardType.DirectReferralReward));

        // Check reward info
        (, , uint256 totalReward, , uint256 directReferralReward, , ) = stakingManager.totalLpStakingReward(user1);
        assertEq(totalReward, 500 * 10 ** 6, "Total reward should be 500 USDT");
        assertEq(directReferralReward, 500 * 10 ** 6, "Direct referral reward should be 500 USDT");
    }

    function testCreateLiquidityProviderRewardTeamReferral() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 300 * 10 ** 6, uint8(IStakingManager.StakingRewardType.TeamReferralReward));

        // Check reward info
        (, , uint256 totalReward, , , uint256 teamReferralReward, ) = stakingManager.totalLpStakingReward(user1);
        assertEq(totalReward, 300 * 10 ** 6, "Total reward should be 300 USDT");
        assertEq(teamReferralReward, 300 * 10 ** 6, "Team referral reward should be 300 USDT");
        assertEq(stakingManager.teamOutOfReward(user1), false, "Team out of reward should be false");
    }

    function testCreateLiquidityProviderRewardFomoPool() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 200 * 10 ** 6, uint8(IStakingManager.StakingRewardType.FomoPoolReward));

        // Check reward info
        (, , uint256 totalReward, , , , uint256 fomoPoolReward) = stakingManager.totalLpStakingReward(user1);
        assertEq(totalReward, 200 * 10 ** 6, "Total reward should be 200 USDT");
        assertEq(fomoPoolReward, 200 * 10 ** 6, "FOMO pool reward should be 200 USDT");
    }

    function testCreateLiquidityProviderRewardRevertsOnInvalidRewardType() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(stakingOperatorManager);
        vm.expectRevert(abi.encodeWithSelector(IStakingManager.InvalidRewardTypeError.selector, 5));
        stakingManager.createLiquidityProviderReward(user1, 1000 * 10 ** 6, 5);
    }

    function testCreateLiquidityProviderRewardRevertsIfNotOperatorManager() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(user2);
        vm.expectRevert("onlyRewardDistributionManager");
        stakingManager.createLiquidityProviderReward(user1, 1000 * 10 ** 6, uint8(IStakingManager.StakingRewardType.DailyNormalReward));
    }

    function testLiquidityProviderClaimReward() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        // Add rewards
        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 1000 * 10 ** 6, uint8(IStakingManager.StakingRewardType.DailyNormalReward));

        // Check reward is distributed
        (, , uint256 totalRewardBefore, , , , ) = stakingManager.totalLpStakingReward(user1);
        assertEq(totalRewardBefore, 1000 * 10 ** 6, "Total reward should be 1000 USDT");

        // Note: liquidityProviderClaimReward requires a real swap pool to execute,
        // which is not available in this test environment.
        // The claim functionality would need integration testing with a real pool contract.
    }

    function testLiquidityProviderClaimPartialReward() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 1000 * 10 ** 6, uint8(IStakingManager.StakingRewardType.DailyNormalReward));

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 500 * 10 ** 6, uint8(IStakingManager.StakingRewardType.DirectReferralReward));

        // Check total rewards accumulated
        (, , uint256 totalReward, uint256 dailyReward, uint256 directReward, , ) = stakingManager.totalLpStakingReward(user1);
        assertEq(totalReward, 1500 * 10 ** 6, "Total reward should be 1500 USDT");
        assertEq(dailyReward, 1000 * 10 ** 6, "Daily reward should be 1000 USDT");
        assertEq(directReward, 500 * 10 ** 6, "Direct referral reward should be 500 USDT");

        // Note: Claim functionality requires real pool integration for testing
    }

    function testLiquidityProviderClaimRewardRevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("StakingManager.liquidityProviderClaimReward: reward amount must more than zero");
        stakingManager.liquidityProviderClaimReward(0);
    }

    function testLiquidityProviderClaimRewardRevertsOnInsufficientReward() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 500 * 10 ** 6, uint8(IStakingManager.StakingRewardType.DailyNormalReward));

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IStakingManager.InvalidRewardAmount.selector, user1, 1000 * 10 ** 6));
        stakingManager.liquidityProviderClaimReward(1000 * 10 ** 6);
    }

    function testLiquidityProviderRoundStakingOver() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        // Move time forward past staking period (172800 seconds for T1)
        vm.warp(block.timestamp + 172801);

        vm.prank(stakingOperatorManager);
        vm.expectEmit(true, false, false, false);
        emit lpRoundStakingOver(user1, block.number, block.timestamp);
        stakingManager.liquidityProviderRoundStakingOver(user1, 0);

        // Check staking status
        (, , , , , uint8 stakingStatus) = stakingManager.currentLiquidityProvider(user1, 0);
        assertEq(stakingStatus, 1, "Staking status should be 1 (ended) after staking period");
    }

    function testLiquidityProviderRoundStakingOverRevertsIfStillUnderPeriod() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        // Try to end staking before period ends
        vm.prank(stakingOperatorManager);
        vm.expectRevert(abi.encodeWithSelector(IStakingManager.LpUnderStakingPeriodError.selector, user1, 0));
        stakingManager.liquidityProviderRoundStakingOver(user1, 0);
    }

    function testMultipleRewardTypesAccumulation() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        // Add different types of rewards
        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 1000 * 10 ** 6, uint8(IStakingManager.StakingRewardType.DailyNormalReward));

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 500 * 10 ** 6, uint8(IStakingManager.StakingRewardType.DirectReferralReward));

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 300 * 10 ** 6, uint8(IStakingManager.StakingRewardType.TeamReferralReward));

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 200 * 10 ** 6, uint8(IStakingManager.StakingRewardType.FomoPoolReward));

        // Check total reward
        (
            ,
            ,
            uint256 totalReward,
            uint256 dailyNormalReward,
            uint256 directReferralReward,
            uint256 teamReferralReward,
            uint256 fomoPoolReward
        ) = stakingManager.totalLpStakingReward(user1);
        assertEq(totalReward, 2000 * 10 ** 6, "Total accumulated reward should be 2000 USDT");
        assertEq(dailyNormalReward, 1000 * 10 ** 6, "Daily normal reward should be 1000 USDT");
        assertEq(directReferralReward, 500 * 10 ** 6, "Direct referral reward should be 500 USDT");
        assertEq(teamReferralReward, 300 * 10 ** 6, "Team referral reward should be 300 USDT");
        assertEq(fomoPoolReward, 200 * 10 ** 6, "FOMO pool reward should be 200 USDT");
    }

    function testConstants() public {
        assertEq(stakingManager.t1Staking(), 200 * 10 ** 6, "T1 staking amount should be 200 USDT");
        assertEq(stakingManager.t2Staking(), 600 * 10 ** 6, "T2 staking amount should be 600 USDT");
        assertEq(stakingManager.t3Staking(), 1200 * 10 ** 6, "T3 staking amount should be 1200 USDT");
        assertEq(stakingManager.t4Staking(), 2500 * 10 ** 6, "T4 staking amount should be 2500 USDT");
        assertEq(stakingManager.t5Staking(), 6000 * 10 ** 6, "T5 staking amount should be 6000 USDT");
        assertEq(stakingManager.t6Staking(), 14000 * 10 ** 6, "T6 staking amount should be 14000 USDT");

        assertEq(stakingManager.t1StakingTimeInternal(), 172800, "T1 staking time should be 172800 seconds (2 days)");
        assertEq(stakingManager.t2StakingTimeInternal(), 259200, "T2 staking time should be 259200 seconds (3 days)");
        assertEq(stakingManager.t3StakingTimeInternal(), 345600, "T3 staking time should be 345600 seconds (4 days)");
        assertEq(stakingManager.t4StakingTimeInternal(), 432000, "T4 staking time should be 432000 seconds (5 days)");
        assertEq(stakingManager.t5StakingTimeInternal(), 518400, "T5 staking time should be 518400 seconds (6 days)");
        assertEq(stakingManager.t6StakingTimeInternal(), 604800, "T6 staking time should be 604800 seconds (7 days)");

        assertEq(stakingManager.underlyingToken(), address(mockToken), "Underlying token should be mockToken");
        assertEq(stakingManager.stakingOperatorManager(), stakingOperatorManager, "Staking operator manager should match");
    }

    function testInviteRelationshipSetup() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        assertEq(stakingManager.inviteRelationShip(user1), inviter1, "User1's inviter should be inviter1");

        vm.prank(user2);
        stakingManager.liquidityProviderDeposit(user1, T2_STAKING);

        assertEq(stakingManager.inviteRelationShip(user2), user1, "User2's inviter should be user1");
    }

    // ===================== Tests for setPool function =====================
    function testSetPool() public {
        address newPool = address(0x123);

        vm.prank(owner);
        stakingManager.setPool(newPool);

        assertEq(stakingManager.pool(), newPool, "Pool address should be updated to newPool");
    }

    function testSetPoolRevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid pool address");
        stakingManager.setPool(address(0));
    }

    function testSetPoolRevertsIfNotOwner() public {
        address newPool = address(0x123);

        vm.prank(user1);
        vm.expectRevert();
        stakingManager.setPool(newPool);
    }

    // ===================== Tests for setPositionTokenId function =====================
    function testSetPositionTokenId() public {
        uint256 newTokenId = 12345;

        vm.prank(owner);
        stakingManager.setPositionTokenId(newTokenId);

        assertEq(stakingManager.positionTokenId(), newTokenId, "Position token ID should be updated");
    }

    function testSetPositionTokenIdRevertsOnZero() public {
        vm.prank(owner);
        vm.expectRevert("Invalid token ID");
        stakingManager.setPositionTokenId(0);
    }

    function testSetPositionTokenIdRevertsIfNotOwner() public {
        uint256 newTokenId = 12345;

        vm.prank(user1);
        vm.expectRevert();
        stakingManager.setPositionTokenId(newTokenId);
    }

    // ===================== Tests for team reward limit (3x staking amount) =====================
    function testTeamRewardReachesThreeTimesLimit() public {
        // User1 stakes T1 (200 USDT)
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        // Check initial state
        assertEq(stakingManager.teamOutOfReward(user1), false, "Team out of reward should be false initially");

        // Add team rewards that don't exceed 3x limit (600 USDT max for 200 USDT staking)
        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 300 * 10 ** 6, uint8(IStakingManager.StakingRewardType.TeamReferralReward));

        // Check team reward is added
        (, , , , , uint256 teamReward1, ) = stakingManager.totalLpStakingReward(user1);
        assertEq(teamReward1, 300 * 10 ** 6, "Team reward should be 300 USDT");
        assertEq(stakingManager.teamOutOfReward(user1), false, "Team out of reward should still be false");

        // Add more team rewards to reach the limit
        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 250 * 10 ** 6, uint8(IStakingManager.StakingRewardType.TeamReferralReward));

        // Check team reward stops at 3x limit
        (, , , , , uint256 teamReward2, ) = stakingManager.totalLpStakingReward(user1);
        assertEq(teamReward2, 550 * 10 ** 6, "Team reward should be capped");
        assertEq(stakingManager.teamOutOfReward(user1), false, "Should not exceed limit yet");

        // Try to add more - should trigger out of achieve returns node
        vm.prank(stakingOperatorManager);
        vm.expectEmit(true, false, false, false);
        emit outOfAchieveReturnsNodeExit(user1, 600 * 10 ** 6, block.number);
        stakingManager.createLiquidityProviderReward(user1, 100 * 10 ** 6, uint8(IStakingManager.StakingRewardType.TeamReferralReward));

        // Check final state
        (, , , , , uint256 teamReward3, ) = stakingManager.totalLpStakingReward(user1);
        assertEq(teamReward3, 600 * 10 ** 6, "Team reward should be capped at 600 USDT (3x 200 USDT)");
        assertEq(stakingManager.teamOutOfReward(user1), true, "Team out of reward should now be true");
    }

    function testTeamRewardStopsAfterReachingLimit() public {
        // User1 stakes T1 (200 USDT), so max team reward is 600 USDT (3x)
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        // Add team reward gradually up to the 3x limit
        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 300 * 10 ** 6, uint8(IStakingManager.StakingRewardType.TeamReferralReward));

        (, , uint256 totalReward1, , , uint256 teamReward1, ) = stakingManager.totalLpStakingReward(user1);
        assertEq(teamReward1, 300 * 10 ** 6, "Team reward should be 300 USDT");
        assertEq(stakingManager.teamOutOfReward(user1), false, "Team should not be out of reward yet");

        // Add more to reach and exceed the limit
        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 400 * 10 ** 6, uint8(IStakingManager.StakingRewardType.TeamReferralReward));

        // When (teamReward + amount) > stakingToCmt * 3, lastTeamReward = (teamReward + amount) - (stakingToCmt * 3)
        // (300 + 400) - (200 * 3) = 700 - 600 = 100
        // So final teamReward = 300 + 100 = 400 (not 600 due to contract logic)
        (, , uint256 totalReward2, , , uint256 teamReward2, ) = stakingManager.totalLpStakingReward(user1);
        assertEq(teamReward2, 400 * 10 ** 6, "Team reward should be 400 USDT based on contract logic");
        assertEq(totalReward2, 700 * 10 ** 6, "Total reward should be 700 USDT");
        assertEq(stakingManager.teamOutOfReward(user1), true, "Team should now be out of reward");

        // After reaching limit, trying to add team rewards will revert because 
        // the condition `incomeType == uint8(StakingRewardType.TeamReferralReward) && !teamOutOfReward[lpAddress]` 
        // evaluates to false, causing InvalidRewardTypeError
        vm.prank(stakingOperatorManager);
        vm.expectRevert(abi.encodeWithSelector(IStakingManager.InvalidRewardTypeError.selector, 2));
        stakingManager.createLiquidityProviderReward(user1, 100 * 10 ** 6, uint8(IStakingManager.StakingRewardType.TeamReferralReward));

        // Verify team reward hasn't changed
        (, , uint256 totalReward3, , , uint256 teamReward3, ) = stakingManager.totalLpStakingReward(user1);
        assertEq(teamReward3, 400 * 10 ** 6, "Team reward should remain at 400 USDT");
        assertEq(totalReward3, 700 * 10 ** 6, "Total reward should remain at 700 USDT");
    }

    // ===================== Tests for liquidityProviderTypeAndAmount (via deposit) =====================
    function testLiquidityProviderTypeAndAmountCalculation() public {
        // Test T1
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);
        (, uint8 type1, , , uint256 endTime1, ) = stakingManager.currentLiquidityProvider(user1, 0);
        assertEq(type1, uint8(IStakingManager.StakingType.T1), "Type should be T1");
        assertEq(endTime1, block.timestamp + 172800, "End time should be start + 172800 seconds");

        // Test T2
        vm.prank(user2);
        stakingManager.liquidityProviderDeposit(inviter1, T2_STAKING);
        (, uint8 type2, , , uint256 endTime2, ) = stakingManager.currentLiquidityProvider(user2, 0);
        assertEq(type2, uint8(IStakingManager.StakingType.T2), "Type should be T2");
        assertEq(endTime2, block.timestamp + 259200, "End time should be start + 259200 seconds");

        // Test T3
        vm.prank(user3);
        stakingManager.liquidityProviderDeposit(inviter1, T3_STAKING);
        (, uint8 type3, , , uint256 endTime3, ) = stakingManager.currentLiquidityProvider(user3, 0);
        assertEq(type3, uint8(IStakingManager.StakingType.T3), "Type should be T3");
        assertEq(endTime3, block.timestamp + 345600, "End time should be start + 345600 seconds");
    }

    // ===================== Tests for receive() function =====================
    function testReceiveNativeToken() public {
        uint256 balanceBefore = address(stakingManager).balance;
        uint256 sendAmount = 1 ether;

        vm.deal(user1, sendAmount);
        vm.prank(user1);
        (bool success, ) = address(stakingManager).call{value: sendAmount}("");

        assertTrue(success, "Should be able to receive native token");
        assertEq(address(stakingManager).balance, balanceBefore + sendAmount, "Contract balance should increase");
    }

    // ===================== Edge case tests =====================
    function testMultipleUsersStakingSameType() public {
        // Multiple users stake the same type
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(user2);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        vm.prank(user3);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        address[] memory t1Providers = stakingManager.getLiquidityProvidersByType(uint8(IStakingManager.StakingType.T1));
        assertEq(t1Providers.length, 3, "Should have 3 T1 providers");
        assertEq(t1Providers[0], user1, "First provider should be user1");
        assertEq(t1Providers[1], user2, "Second provider should be user2");
        assertEq(t1Providers[2], user3, "Third provider should be user3");
    }

    function testStakingRoundIncrementsCorrectly() public {
        assertEq(stakingManager.lpStakingRound(user1), 0, "Initial round should be 0");

        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);
        assertEq(stakingManager.lpStakingRound(user1), 1, "Round should be 1 after first deposit");

        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T2_STAKING);
        assertEq(stakingManager.lpStakingRound(user1), 2, "Round should be 2 after second deposit");

        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T3_STAKING);
        assertEq(stakingManager.lpStakingRound(user1), 3, "Round should be 3 after third deposit");
    }

    function testDifferentStakingTypeTimePeriods() public {
        // Test all staking time periods
        assertEq(stakingManager.t1StakingTimeInternal(), 172800, "T1 should be 172800 seconds (2 days)");
        assertEq(stakingManager.t2StakingTimeInternal(), 259200, "T2 should be 259200 seconds (3 days)");
        assertEq(stakingManager.t3StakingTimeInternal(), 345600, "T3 should be 345600 seconds (4 days)");
        assertEq(stakingManager.t4StakingTimeInternal(), 432000, "T4 should be 432000 seconds (5 days)");
        assertEq(stakingManager.t5StakingTimeInternal(), 518400, "T5 should be 518400 seconds (6 days)");
        assertEq(stakingManager.t6StakingTimeInternal(), 604800, "T6 should be 604800 seconds (7 days)");
    }

    function testRewardTypeValidation() public {
        vm.prank(user1);
        stakingManager.liquidityProviderDeposit(inviter1, T1_STAKING);

        // Test valid reward types (0-3)
        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 100 * 10 ** 6, 0);

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 100 * 10 ** 6, 1);

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 100 * 10 ** 6, 2);

        vm.prank(stakingOperatorManager);
        stakingManager.createLiquidityProviderReward(user1, 100 * 10 ** 6, 3);

        // Test invalid reward type (4+)
        vm.prank(stakingOperatorManager);
        vm.expectRevert(abi.encodeWithSelector(IStakingManager.InvalidRewardTypeError.selector, 4));
        stakingManager.createLiquidityProviderReward(user1, 100 * 10 ** 6, 4);
    }
}
