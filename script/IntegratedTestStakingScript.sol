// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import {IPancakeV2Factory} from "../src/interfaces/staking/pancake/IPancakeV2Factory.sol";
import {IPancakeV2Router} from "../src/interfaces/staking/pancake/IPancakeV2Router.sol";
import {IPancakeV2Pair} from "../src/interfaces/staking/pancake/IPancakeV2Pair.sol";

import {EmptyContract} from "../src/utils/EmptyContract.sol";
import {ChooseMeToken} from "../src/token/ChooseMeToken.sol";
import {ChooseMeTokenStorage} from "../src/token/ChooseMeTokenStorage.sol";
import {IChooseMeToken} from "../src/interfaces/token/IChooseMeToken.sol";
import {NodeManager} from "../src/staking/NodeManager.sol";
import {StakingManager} from "../src/staking/StakingManager.sol";
import {DaoRewardManager} from "../src/token/allocation/DaoRewardManager.sol";
import {FomoTreasureManager} from "../src/token/allocation/FomoTreasureManager.sol";
import {AirdropManager} from "../src/token/allocation/AirdropManager.sol";
import {EventFundingManager} from "../src/staking/EventFundingManager.sol";
import {SubTokenFundingManager} from "../src/staking/SubTokenFundingManager.sol";

/**
 * @title MockUSDT
 * @notice Mock USDT token for testing purposes
 */
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 10000000 * 10 ** 18);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title IntegratedTestStakingScript
 * @notice Integrated test script for StakingManager and NodeManager
 * @dev Tests the complete workflow including staking, node purchase, rewards distribution and claiming
 *
 * Run with: forge script IntegratedTestStakingScript --rpc-url https://bsc-dataseed.binance.org  --broadcast -vvvv
 */
contract IntegratedTestStakingScript is Script {
    // Contract instances
    ChooseMeToken public chooseMeToken;
    NodeManager public nodeManager;
    StakingManager public stakingManager;
    DaoRewardManager public daoRewardManager;
    FomoTreasureManager public fomoTreasureManager;
    AirdropManager public airdropManager;
    EventFundingManager public eventFundingManager;
    SubTokenFundingManager public subTokenFundingManager;
    MockUSDT public usdt;

    // Proxy contracts
    ProxyAdmin public proxyAdmin;
    uint256 deployerPrivateKey;

    // Test accounts
    address public owner;
    address public stakingOperatorManager;
    address public distributeRewardAddress;
    address public liquidityProvider1;
    address public liquidityProvider2;
    address public nodeOperator1;
    address public nodeOperator2;

    // Constants
    address public constant V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    function setUp() public {}

    function run() public {
        console.log("=== Starting Integrated Staking Tests ===");

        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy all contracts
        deployContracts();

        // Setup test accounts
        setupTestAccounts();

        // Add initial liquidity to PancakeSwap for CMT/USDT pair
        addInitialLiquidity();

        vm.stopBroadcast();

        // Bind inviters for test accounts
        bindTestAccountsInviters();

        // Test 1: StakingManager - Add Liquidity
        testStakingManagerAddLiquidity();

        // Test 2: StakingManager - LP Deposit and Claim Rewards
        testStakingManagerLPFlow();

        // Test 3: NodeManager - Add Liquidity
        testNodeManagerAddLiquidity();

        // Test 4: NodeManager - Node Purchase and Claim Rewards
        testNodeManagerFlow();

        console.log("=== All Integrated Tests Completed ===");
        require(false, "End of Integrated Test Script");
    }

    function deployContracts() internal {
        console.log("Deploying contracts...");

        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(owner);

        // Deploy MockUSDT
        usdt = new MockUSDT();
        console.log("MockUSDT deployed at:", address(usdt));

        // Deploy ChooseMeToken
        ChooseMeToken chooseMeTokenImpl = new ChooseMeToken();
        TransparentUpgradeableProxy chooseMeTokenProxy =
            new TransparentUpgradeableProxy(address(chooseMeTokenImpl), address(proxyAdmin), "");
        chooseMeToken = ChooseMeToken(address(chooseMeTokenProxy));

        chooseMeToken.initialize(owner, owner, address(usdt)); // stakingManager placeholder, will be set later
        console.log("ChooseMeToken deployed at:", address(chooseMeToken));

        // Deploy EventFundingManager first (no dependencies)
        EventFundingManager eventFundingManagerImpl = new EventFundingManager();
        TransparentUpgradeableProxy eventFundingManagerProxy =
            new TransparentUpgradeableProxy(address(eventFundingManagerImpl), address(proxyAdmin), "");
        eventFundingManager = EventFundingManager(payable(address(eventFundingManagerProxy)));

        eventFundingManager.initialize(owner, address(usdt));
        console.log("EventFundingManager deployed at:", address(eventFundingManager));

        // Deploy proxy placeholders for StakingManager and NodeManager
        stakingOperatorManager = owner;
        distributeRewardAddress = owner;

        StakingManager stakingManagerImpl = new StakingManager();
        TransparentUpgradeableProxy stakingManagerProxy =
            new TransparentUpgradeableProxy(address(stakingManagerImpl), address(proxyAdmin), "");
        stakingManager = StakingManager(payable(address(stakingManagerProxy)));

        NodeManager nodeManagerImpl = new NodeManager();
        TransparentUpgradeableProxy nodeManagerProxy =
            new TransparentUpgradeableProxy(address(nodeManagerImpl), address(proxyAdmin), "");
        nodeManager = NodeManager(address(nodeManagerProxy));

        console.log("StakingManager proxy deployed at:", address(stakingManager));
        console.log("NodeManager proxy deployed at:", address(nodeManager));

        // Now deploy DaoRewardManager with the correct addresses
        DaoRewardManager daoRewardManagerImpl = new DaoRewardManager();
        TransparentUpgradeableProxy daoRewardManagerProxy =
            new TransparentUpgradeableProxy(address(daoRewardManagerImpl), address(proxyAdmin), "");
        daoRewardManager = DaoRewardManager(payable(address(daoRewardManagerProxy)));

        daoRewardManager.initialize(owner, address(chooseMeToken), address(nodeManager), address(stakingManager));
        console.log("DaoRewardManager deployed at:", address(daoRewardManager));

        // Deploy AirdropManager
        AirdropManager airdropManagerImpl = new AirdropManager();
        TransparentUpgradeableProxy airdropManagerProxy =
            new TransparentUpgradeableProxy(address(airdropManagerImpl), address(proxyAdmin), "");
        airdropManager = AirdropManager(payable(address(airdropManagerProxy)));

        airdropManager.initialize(owner, address(chooseMeToken));
        console.log("AirdropManager deployed at:", address(airdropManager));

        // Initialize StakingManager
        stakingManager.initialize(
            owner,
            address(chooseMeToken),
            address(usdt),
            stakingOperatorManager,
            address(daoRewardManager),
            address(eventFundingManager),
            address(nodeManager),
            address(subTokenFundingManager)
        );
        console.log("StakingManager initialized");

        // Update ChooseMeToken stakingManager address
        chooseMeToken.setStakingManager(address(stakingManager));

        // Initialize NodeManager
        nodeManager.initialize(
            owner,
            address(daoRewardManager),
            address(chooseMeToken),
            address(usdt),
            distributeRewardAddress,
            address(eventFundingManager)
        );
        console.log("NodeManager initialized");

        // Setup pool addresses and allocate tokens
        IChooseMeToken.ChooseMePool memory pool = IChooseMeToken.ChooseMePool({
            nodePool: owner, // For testing
            daoRewardPool: address(daoRewardManager),
            airdropPool: address(airdropManager),
            techRewardsPool: owner,
            foundingStrategyPool: owner,
            marketingPool: owner,
            subTokenPool: owner
        });
        address[] memory marketingPools = new address[](1);
        marketingPools[0] = owner;
        address[] memory ecosystemPools = new address[](1);
        ecosystemPools[0] = owner;
        chooseMeToken.setPoolAddress(pool, marketingPools, ecosystemPools);
        chooseMeToken.poolAllocate();
        console.log("Token pools allocated");

        uint256 daoBalance = chooseMeToken.balanceOf(address(daoRewardManager));
        console.log("DaoRewardManager CMT balance:", daoBalance / 10 ** 6);
    }

    function addInitialLiquidity() internal {
        console.log("\n=== Adding Initial Liquidity to PancakeSwap ===");

        uint256 cmtAmount = 100000 * 10 ** 6; // 100,000 CMT
        uint256 usdtAmount = 10000 * 10 ** 18; // 10,000 USDT

        // Approve PancakeSwap Router
        chooseMeToken.approve(V2_ROUTER, cmtAmount);
        usdt.approve(V2_ROUTER, usdtAmount);

        console.log("Approved tokens for router");
        console.log("CMT amount:", cmtAmount / 10 ** 6);
        console.log("USDT amount:", usdtAmount / 10 ** 18);

        // Add liquidity through PancakeSwap Router
        IPancakeV2Router router = IPancakeV2Router(V2_ROUTER);
        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            address(chooseMeToken),
            address(usdt),
            cmtAmount,
            usdtAmount,
            cmtAmount * 95 / 100, // 5% slippage tolerance
            usdtAmount * 95 / 100,
            owner,
            block.timestamp + 300 // 5 minutes deadline
        );

        console.log("Liquidity added successfully");
        console.log("CMT added:", amountA / 10 ** 6);
        console.log("USDT added:", amountB / 10 ** 18);
        console.log("LP tokens received:", liquidity / 10 ** 18);
    }

    function setupTestAccounts() internal {
        console.log("\n=== Setting up test accounts ===");

        // Derive test accounts from MNEMONIC
        string memory mnemonic = vm.envString("MNEMONIC");
        liquidityProvider1 = vm.addr(vm.deriveKey(mnemonic, 1));
        liquidityProvider2 = vm.addr(vm.deriveKey(mnemonic, 2));
        nodeOperator1 = vm.addr(vm.deriveKey(mnemonic, 3));
        nodeOperator2 = vm.addr(vm.deriveKey(mnemonic, 4));

        // Transfer USDT to test accounts
        uint256 testAmount = 50000 * 10 ** 18;
        usdt.transfer(liquidityProvider1, testAmount);
        usdt.transfer(liquidityProvider2, testAmount);
        usdt.transfer(nodeOperator1, testAmount);
        usdt.transfer(nodeOperator2, testAmount);

        // Transfer USDT to StakingManager and NodeManager for adding liquidity
        usdt.transfer(address(stakingManager), testAmount);
        usdt.transfer(address(nodeManager), testAmount);

        console.log("Test accounts setup completed");
    }

    function bindTestAccountsInviters() internal {
        console.log("\n=== Binding Inviters for Test Accounts ===");

        string memory mnemonic = vm.envString("MNEMONIC");
        uint256 lp1PrivateKey = vm.deriveKey(mnemonic, 1);
        address lp1Address = vm.addr(lp1PrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        // Bind liquidityProvider to owner
        nodeManager.bindRootInviter(owner, lp1Address);
        console.log("Owner set as root inviter :", owner, lp1Address);
        vm.stopBroadcast();

        // Bind liquidityProvider2 to lp1Address
        uint256 lp2PrivateKey = vm.deriveKey(mnemonic, 2);
        vm.startBroadcast(lp2PrivateKey);
        nodeManager.bindInviter(lp1Address);
        console.log("LP2 bound inviter:", lp1Address);
        vm.stopBroadcast();

        // Bind nodeOperator1 to lp1Address
        uint256 nodeOp1PrivateKey = vm.deriveKey(mnemonic, 3);
        vm.startBroadcast(nodeOp1PrivateKey);
        nodeManager.bindInviter(lp1Address);
        console.log("Node Operator 1 bound inviter:", lp1Address);
        vm.stopBroadcast();

        // Bind nodeOperator2 to lp1Address
        uint256 nodeOp2PrivateKey = vm.deriveKey(mnemonic, 4);
        vm.startBroadcast(nodeOp2PrivateKey);
        nodeManager.bindInviter(lp1Address);
        console.log("Node Operator 2 bound inviter:", lp1Address);
        vm.stopBroadcast();

        console.log("All test accounts bound to owner as inviter");
    }

    function testStakingManagerAddLiquidity() internal {
        console.log("\n=== Test 1: StakingManager Add Liquidity ===");

        uint256 liquidityAmount = 1000 * 10 ** 18;

        // Approve tokens for StakingManager
        uint256 stakingManagerUsdtBalance = usdt.balanceOf(address(stakingManager));
        console.log("StakingManager USDT balance:", stakingManagerUsdtBalance / 10 ** 18);

        if (stakingManagerUsdtBalance >= liquidityAmount) {
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
            vm.startBroadcast(deployerPrivateKey);
            stakingManager.addLiquidity(liquidityAmount);
            console.log("Successfully added liquidity via StakingManager");
            console.log("Liquidity amount:", liquidityAmount / 10 ** 18, "USDT");
            vm.stopBroadcast();
        } else {
            console.log("Insufficient USDT balance for adding liquidity");
        }
    }

    function testStakingManagerLPFlow() internal {
        console.log("\n=== Test 2: StakingManager LP Flow ===");

        // LP1 deposits stake
        uint256 stakeAmount = 200 * 10 ** 18; // T1 staking

        string memory mnemonic = vm.envString("MNEMONIC");
        uint256 lp1PrivateKey = vm.deriveKey(mnemonic, 1);

        vm.startBroadcast(lp1PrivateKey);
        usdt.approve(address(stakingManager), stakeAmount);

        stakingManager.liquidityProviderDeposit(stakeAmount);
        console.log("LP1 deposited:", stakeAmount / 10 ** 18, "USDT");

        vm.stopBroadcast();

        // Simulate reward distribution
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        uint256 rewardAmount = 10 * 10 ** 6;

        stakingManager.createLiquidityProviderReward(liquidityProvider1, 0, rewardAmount, rewardAmount, 0);
        console.log("Distributed reward to LP1:", rewardAmount / 10 ** 6, "CMT");
        vm.stopBroadcast();

        // LP1 claims reward
        vm.startBroadcast(lp1PrivateKey);
        uint256 claimAmount = 5 * 10 ** 6;

        stakingManager.liquidityProviderClaimReward(claimAmount);
        console.log("LP1 claimed reward:", claimAmount / 10 ** 6, "CMT");
        uint256 lpBalance = chooseMeToken.balanceOf(liquidityProvider1);
        console.log("LP1 CMT balance after claim:", lpBalance / 10 ** 6);
        vm.stopBroadcast();
    }

    function testNodeManagerAddLiquidity() internal {
        console.log("\n=== Test 3: NodeManager Add Liquidity ===");

        uint256 liquidityAmount = 1000 * 10 ** 18;

        uint256 nodeManagerUsdtBalance = usdt.balanceOf(address(nodeManager));
        console.log("NodeManager USDT balance:", nodeManagerUsdtBalance / 10 ** 18);

        if (nodeManagerUsdtBalance >= liquidityAmount) {
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
            vm.startBroadcast(deployerPrivateKey);
            nodeManager.addLiquidity(liquidityAmount);
            console.log("Successfully added liquidity via NodeManager");
            console.log("Liquidity amount:", liquidityAmount / 10 ** 18, "USDT");
            vm.stopBroadcast();
        } else {
            console.log("Insufficient USDT balance for adding liquidity");
        }
    }

    function testNodeManagerFlow() internal {
        console.log("\n=== Test 4: NodeManager Purchase and Claim Flow ===");

        // Node operator purchases node
        uint256 nodePrice = 500 * 10 ** 18; // Distributed node

        string memory mnemonic = vm.envString("MNEMONIC");
        uint256 nodeOp1PrivateKey = vm.deriveKey(mnemonic, 3);

        vm.startBroadcast(nodeOp1PrivateKey);
        usdt.approve(address(nodeManager), nodePrice);

        nodeManager.purchaseNode(nodePrice);
        console.log("Node operator 1 purchased node:", nodePrice / 10 ** 18, "USDT");
        vm.stopBroadcast();

        // Distribute node rewards
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        uint256 rewardAmount = 20 * 10 ** 6;

        nodeManager.distributeRewards(nodeOperator1, rewardAmount, rewardAmount, 0);
        console.log("Distributed reward to node operator 1:", rewardAmount / 10 ** 6, "CMT");
        vm.stopBroadcast();

        // Node operator claims reward
        vm.startBroadcast(nodeOp1PrivateKey);
        uint256 claimAmount = 10 * 10 ** 6;

        nodeManager.claimReward(claimAmount);
        console.log("Node operator 1 claimed reward:", claimAmount / 10 ** 6, "CMT");
        uint256 nodeOperatorBalance = chooseMeToken.balanceOf(nodeOperator1);
        console.log("Node operator 1 CMT balance after claim:", nodeOperatorBalance / 10 ** 6);
        vm.stopBroadcast();
    }
}
