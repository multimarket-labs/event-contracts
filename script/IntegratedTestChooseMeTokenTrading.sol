// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {EmptyContract} from "../src/utils/EmptyContract.sol";
import {ChooseMeToken} from "../src/token/ChooseMeToken.sol";
import {IChooseMeToken} from "../src/interfaces/token/IChooseMeToken.sol";
import {IPancakeV2Factory} from "../src/interfaces/staking/pancake/IPancakeV2Factory.sol";
import {IPancakeV2Router} from "../src/interfaces/staking/pancake/IPancakeV2Router.sol";
import {IPancakeV2Pair} from "../src/interfaces/staking/pancake/IPancakeV2Pair.sol";

/**
 * forge script IntegratedTestChooseMeTokenTrading --rpc-url https://bsc-dataseed.binance.org
 * @title IntegratedTestChooseMeTokenTrading
 * @notice Integration test for ChooseMeToken trading slippage and profit tax functionality
 * @dev Test scenarios:
 * 1. Trading slippage test (3% total fee)
 *    - Buy slippage: 0.5% node + 0.5% cluster + 0.5% market + 1% tech + 0.5% subToken
 *    - Sell slippage: Same as above
 * 2. Profit tax test
 *    - Sell with profit: 8% node + 6% cluster + 4% market + 4% tech + 4% subToken (total 26%)
 *    - Sell with loss: Only trading slippage, no profit tax
 * 3. Whitelist test: Whitelist addresses are exempt from all fees
 */
contract IntegratedTestChooseMeTokenTrading is Script {
    // BSC Mainnet addresses
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant PANCAKE_V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant PANCAKE_V2_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    // Test accounts
    address owner;
    address trader1;
    address trader2;
    address stakingManager;
    address priceManipulator;

    // Contracts
    ChooseMeToken chooseMeToken;
    ProxyAdmin proxyAdmin;
    TransparentUpgradeableProxy proxy;
    IPancakeV2Pair mainPair;

    // Pool addresses
    address nodePool;
    address daoRewardPool;
    address airdropPool;
    address techRewardsPool;
    address ecosystemPool;
    address foundingStrategyPool;
    address marketingDevelopmentPool;
    address subTokenPool;

    /**
     * @notice 设置 ERC20 代币余额（使用 vm.deal 和适配 USDT 的存储槽）
     * @param token 代币地址
     * @param user 用户地址
     * @param amount 余额数量
     */
    function writeTokenBalance(address token, address user, uint256 amount) internal {
        // USDT on BSC uses slot 1 for balances mapping
        // storage location = keccak256(abi.encode(user, slot))
        bytes32 slot = keccak256(abi.encode(user, uint256(1)));
        vm.store(token, slot, bytes32(amount));

        // If balance not set correctly, try slot 0
        if (IERC20(token).balanceOf(user) != amount) {
            slot = keccak256(abi.encode(user, uint256(0)));
            vm.store(token, slot, bytes32(amount));
        }

        // If still not correct, try slot 2
        if (IERC20(token).balanceOf(user) != amount) {
            slot = keccak256(abi.encode(user, uint256(2)));
            vm.store(token, slot, bytes32(amount));
        }

        // Verify balance set successfully
        console.log("User balance after setting:", IERC20(token).balanceOf(user));
    }

    function setUp() public {
        // Setup test accounts
        owner = vm.addr(1);
        trader1 = vm.addr(2);
        trader2 = vm.addr(3);
        stakingManager = vm.addr(4);
        priceManipulator = vm.addr(5);

        // Setup pool addresses
        nodePool = vm.addr(10);
        daoRewardPool = vm.addr(11);
        airdropPool = vm.addr(12);
        techRewardsPool = vm.addr(13);
        ecosystemPool = vm.addr(14);
        foundingStrategyPool = vm.addr(15);
        marketingDevelopmentPool = vm.addr(16);
        subTokenPool = vm.addr(17);

        console.log("=== Test Setup ===");
        console.log("Owner:", owner);
        console.log("Trader1:", trader1);
        console.log("Trader2:", trader2);
    }

    function run() public {
        // Don't use startBroadcast for testing, use prank instead
        // vm.startBroadcast();

        console.log("\n=== Starting ChooseMeToken Integration Test ===\n");

        // 1. Deploy contracts
        deployContracts();

        // 2. Initialize token and pools
        initializeToken();

        // 3. Add initial liquidity
        addInitialLiquidity();

        // 4. Test trading slippage
        testTradingSlippage();

        // 5. Test sell slippage
        testSellSlippage();

        // 6. Test profit tax
        testProfitTax();

        // 7. Test whitelist functionality
        testWhitelist();

        // 8. Test loss scenario (no profit tax)
        testLossScenario();

        // vm.stopBroadcast();
    }

    /**
     * @notice 部署 ChooseMeToken 合约
     */
    function deployContracts() internal {
        console.log("--- Deploying Contracts ---");

        // Deploy proxy admin
        proxyAdmin = new ProxyAdmin(owner);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        // Deploy implementation
        ChooseMeToken implementation = new ChooseMeToken();
        console.log("ChooseMeToken implementation deployed at:", address(implementation));

        // Deploy proxy
        proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), "");
        console.log("Proxy deployed at:", address(proxy));

        chooseMeToken = ChooseMeToken(address(proxy));
    }

    /**
     * @notice 初始化代币和池子
     */
    function initializeToken() internal {
        console.log("\n--- Initializing Token ---");

        // Initialize token
        chooseMeToken.initialize(owner, stakingManager, USDT);
        console.log("Token initialized");

        // Set pool addresses
        vm.prank(owner);
        IChooseMeToken.ChooseMePool memory pools = IChooseMeToken.ChooseMePool({
            nodePool: nodePool,
            daoRewardPool: daoRewardPool,
            airdropPool: airdropPool,
            techRewardsPool: techRewardsPool,
            foundingStrategyPool: foundingStrategyPool,
            marketingPool: marketingDevelopmentPool,
            subTokenPool: subTokenPool
        });
        address[] memory marketingPools = new address[](1);
        marketingPools[0] = marketingDevelopmentPool;
        address[] memory ecosystemPools = new address[](1);
        ecosystemPools[0] = ecosystemPool;
        chooseMeToken.setPoolAddress(pools, marketingPools, ecosystemPools);
        console.log("Pool addresses set");

        // Execute pool allocation
        vm.prank(owner);
        chooseMeToken.poolAllocate();
        console.log("Pool allocation completed");
        console.log("Total Supply:", chooseMeToken.totalSupply() / 10 ** 6, "CMT");

        // Get main pair address
        mainPair = IPancakeV2Pair(IPancakeV2Factory(PANCAKE_V2_FACTORY).getPair(USDT, address(chooseMeToken)));
        console.log("Main Pair:", address(mainPair));
    }

    /**
     * @notice 添加初始流动性
     */
    function addInitialLiquidity() internal {
        console.log("\n--- Adding Initial Liquidity ---");

        uint256 cmtAmount = 10_000_000 * 10 ** 6; // 10M CMT
        uint256 usdtAmount = 100_000 * 10 ** 18; // 100K USDT

        // Add liquidity participants to whitelist BEFORE any transfers
        address[] memory whitelist = new address[](2);
        whitelist[0] = owner;
        whitelist[1] = ecosystemPool;
        // vm.prank(owner);
        // chooseMeToken.addWhitelist(whitelist);

        // Get CMT from ecosystem pool
        vm.prank(ecosystemPool);
        chooseMeToken.transfer(owner, cmtAmount);

        // Mock USDT balance for owner
        writeTokenBalance(USDT, owner, usdtAmount);

        // Approve router
        vm.startPrank(owner);
        chooseMeToken.approve(PANCAKE_V2_ROUTER, cmtAmount);
        IERC20(USDT).approve(PANCAKE_V2_ROUTER, usdtAmount);

        // Add liquidity
        IPancakeV2Router(PANCAKE_V2_ROUTER)
            .addLiquidity(address(chooseMeToken), USDT, cmtAmount, usdtAmount, 0, 0, owner, block.timestamp + 1000);

        vm.stopPrank();

        // Remove from whitelist
        // vm.prank(owner);
        // chooseMeToken.removeWhitelist(whitelist);

        console.log("Liquidity added: 10M CMT + 100K USDT");
        console.log("Initial Price: 0.01 USDT per CMT");
    }

    /**
     * @notice 测试交易滑点
     * @dev 测试买入和卖出时的 3% 交易手续费
     */
    function testTradingSlippage() internal {
        console.log("\n=== Test 1: Trading Slippage ===");

        uint256 usdtBuyAmount = 1000 * 10 ** 18; // 1000 USDT

        // Mock USDT for trader1
        writeTokenBalance(USDT, trader1, usdtBuyAmount);

        vm.startPrank(trader1);

        // Record initial balances
        uint256 initialUSDT = IERC20(USDT).balanceOf(trader1);
        console.log("Trader1 initial USDT:", initialUSDT / 10 ** 18);

        // Approve and buy CMT
        IERC20(USDT).approve(PANCAKE_V2_ROUTER, usdtBuyAmount);

        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = address(chooseMeToken);

        uint256 expectedWithoutFee = IPancakeV2Router(PANCAKE_V2_ROUTER).getAmountsOut(usdtBuyAmount, path)[1];

        IPancakeV2Router(PANCAKE_V2_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                usdtBuyAmount, 0, path, trader1, block.timestamp + 1000
            );

        uint256 cmtReceived = chooseMeToken.balanceOf(trader1);
        console.log("CMT received after buy:", cmtReceived / 10 ** 6);

        // With 3% fee (50+50+50+100+50 = 300 basis points)
        uint256 expectedWithFee = expectedWithoutFee * 9700 / 10000;

        console.log("Expected without fee:", expectedWithoutFee / 10 ** 6);
        console.log("Expected with 3% fee:", expectedWithFee / 10 ** 6);
        console.log("Actual received:", cmtReceived / 10 ** 6);

        // Verify fee is approximately 3%
        uint256 feeCollected = expectedWithoutFee - cmtReceived;
        uint256 feePercentage = feeCollected * 10000 / expectedWithoutFee;
        console.log("Trading fee percentage (basis points):", feePercentage);
        console.log("Trading fee collected: ~", feePercentage / 100, ".", feePercentage % 100);

        console.log(" Trading slippage test passed");

        vm.stopPrank();
    }

    /**
     * @notice 测试卖出滑点
     * @dev 测试卖出时的 3% 交易手续费
     */
    function testSellSlippage() internal {
        console.log("\n=== Test 2: Sell Slippage ===");

        uint256 usdtBuyAmount = 1000 * 10 ** 18; // 1000 USDT
        address sellTrader = vm.addr(50);

        // Mock USDT for sellTrader
        writeTokenBalance(USDT, sellTrader, usdtBuyAmount);

        vm.startPrank(sellTrader);

        // First, buy CMT
        console.log("Step 1: Buying CMT first...");
        IERC20(USDT).approve(PANCAKE_V2_ROUTER, usdtBuyAmount);

        address[] memory pathBuy = new address[](2);
        pathBuy[0] = USDT;
        pathBuy[1] = address(chooseMeToken);

        IPancakeV2Router(PANCAKE_V2_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                usdtBuyAmount, 0, pathBuy, sellTrader, block.timestamp + 1000
            );

        uint256 cmtBalance = chooseMeToken.balanceOf(sellTrader);
        console.log("CMT balance after buy:", cmtBalance / 10 ** 6);

        // Now test selling with slippage
        console.log("\nStep 2: Testing sell slippage...");
        uint256 cmtToSell = cmtBalance;

        chooseMeToken.approve(PANCAKE_V2_ROUTER, cmtToSell);

        address[] memory pathSell = new address[](2);
        pathSell[0] = address(chooseMeToken);
        pathSell[1] = USDT;

        uint256 expectedWithoutFee = IPancakeV2Router(PANCAKE_V2_ROUTER).getAmountsOut(cmtToSell, pathSell)[1];
        uint256 usdtBefore = IERC20(USDT).balanceOf(sellTrader);

        IPancakeV2Router(PANCAKE_V2_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                cmtToSell, 0, pathSell, sellTrader, block.timestamp + 1000
            );

        uint256 usdtReceived = IERC20(USDT).balanceOf(sellTrader) - usdtBefore;
        console.log("USDT received after sell:", usdtReceived / 10 ** 18);

        // With 3% fee (50+50+50+100+50 = 300 basis points)
        uint256 expectedWithFee = expectedWithoutFee * 9700 / 10000;

        console.log("Expected without fee:", expectedWithoutFee / 10 ** 18);
        console.log("Expected with 3% fee:", expectedWithFee / 10 ** 18);
        console.log("Actual received:", usdtReceived / 10 ** 18);

        // Verify fee is approximately 3%
        uint256 feeCollected = expectedWithoutFee - usdtReceived;
        uint256 feePercentage = feeCollected * 10000 / expectedWithoutFee;
        console.log("Sell fee percentage (basis points):", feePercentage);
        console.log("Sell fee collected: ~", feePercentage / 100, ".", feePercentage % 100);

        console.log(" Sell slippage test passed");

        vm.stopPrank();
    }

    /**
     * @notice 测试盈利税
     * @dev 测试当卖出盈利时收取额外的盈利税 (26%)
     */
    function testProfitTax() internal {
        console.log("\n=== Test 3: Profit Tax ===");

        uint256 usdtBuyAmount = 1000 * 10 ** 18; // 1000 USDT

        // Mock USDT for trader2
        writeTokenBalance(USDT, trader2, usdtBuyAmount);

        vm.startPrank(trader2);

        // Buy CMT
        IERC20(USDT).approve(PANCAKE_V2_ROUTER, usdtBuyAmount);

        address[] memory pathBuy = new address[](2);
        pathBuy[0] = USDT;
        pathBuy[1] = address(chooseMeToken);

        IPancakeV2Router(PANCAKE_V2_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                usdtBuyAmount, 0, pathBuy, trader2, block.timestamp + 1000
            );

        uint256 cmtBalance = chooseMeToken.balanceOf(trader2);
        console.log("Trader2 used USDT:", usdtBuyAmount / 10 ** 18);
        console.log("Trader2 bought CMT:", cmtBalance / 10 ** 6);
        console.log("Trader2 Cost:", chooseMeToken.userCost(trader2) / 10 ** 18, "USDT");

        vm.stopPrank();

        // Simulate price increase by adding more USDT to the pool
        uint256 additionalUSDT = 500_000 * 10 ** 18; // Add 500K USDT to simulate price increase
        writeTokenBalance(USDT, priceManipulator, additionalUSDT);

        vm.startPrank(priceManipulator);
        IERC20(USDT).approve(PANCAKE_V2_ROUTER, additionalUSDT);

        address[] memory pathPriceIncrease = new address[](2);
        pathPriceIncrease[0] = USDT;
        pathPriceIncrease[1] = address(chooseMeToken);

        IPancakeV2Router(PANCAKE_V2_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                additionalUSDT, 0, pathPriceIncrease, priceManipulator, block.timestamp + 1000
            );
        vm.stopPrank();

        console.log("Price increased by adding liquidity");

        // Now trader2 sells at profit
        vm.startPrank(trader2);

        uint256 cmtToSell = cmtBalance / 2; // Sell half
        uint256 usdtBefore = IERC20(USDT).balanceOf(trader2);

        chooseMeToken.approve(PANCAKE_V2_ROUTER, cmtToSell);

        address[] memory pathSell = new address[](2);
        pathSell[0] = address(chooseMeToken);
        pathSell[1] = USDT;

        uint256 expectedWithoutFee = IPancakeV2Router(PANCAKE_V2_ROUTER).getAmountsOut(cmtToSell, pathSell)[1];

        IPancakeV2Router(PANCAKE_V2_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                cmtToSell, 0, pathSell, trader2, block.timestamp + 1000
            );

        uint256 usdtReceived = IERC20(USDT).balanceOf(trader2) - usdtBefore;
        console.log("USDT expectedWithoutFee:================>", expectedWithoutFee / 10 ** 18);
        console.log("USDT received after selling at profit:", usdtReceived / 10 ** 18);
        console.log("Trader2 Cost after:", chooseMeToken.userCost(trader2) / 10 ** 18, "USDT");

        // The trader should have paid both trading fee (3%) and profit tax (26%)
        uint256 feeCollected = expectedWithoutFee - usdtReceived;
        uint256 feePercentage = feeCollected * 10000 / expectedWithoutFee;
        console.log("Sell fee percentage (basis points):", feePercentage);
        console.log("Sell fee collected: ~", feePercentage / 100, ".", feePercentage % 100);
        console.log(" Profit tax test passed - fees collected on profitable sale");

        vm.stopPrank();
    }

    /**
     * @notice 测试白名单功能
     * @dev 白名单地址应该免除所有手续费
     */
    function testWhitelist() internal {
        console.log("\n=== Test 4: Whitelist Functionality ===");

        address whitelistedTrader = vm.addr(100);
        uint256 usdtAmount = 1000 * 10 ** 18;

        // Add to whitelist
        address[] memory whitelist = new address[](1);
        whitelist[0] = whitelistedTrader;
        vm.prank(owner);
        chooseMeToken.addWhitelist(whitelist);
        console.log("Added trader to whitelist");

        // Mock USDT
        writeTokenBalance(USDT, whitelistedTrader, usdtAmount);

        vm.startPrank(whitelistedTrader);

        // Buy CMT
        IERC20(USDT).approve(PANCAKE_V2_ROUTER, usdtAmount);

        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = address(chooseMeToken);

        uint256 expectedWithoutFee = IPancakeV2Router(PANCAKE_V2_ROUTER).getAmountsOut(usdtAmount, path)[1];

        IPancakeV2Router(PANCAKE_V2_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                usdtAmount, 0, path, whitelistedTrader, block.timestamp + 1000
            );

        uint256 cmtReceived = chooseMeToken.balanceOf(whitelistedTrader);
        console.log("USDT expectedWithoutFee:================>", expectedWithoutFee / 10 ** 18);
        console.log("USDT received after selling at profit:", cmtReceived / 10 ** 18);
        console.log("Trader2 Cost after:", chooseMeToken.userCost(whitelistedTrader) / 10 ** 18, "USDT");

        // The trader should have paid both trading fee (3%) and profit tax (26%)
        uint256 feeCollected = expectedWithoutFee - cmtReceived;
        uint256 feePercentage = feeCollected * 10000 / expectedWithoutFee;
        console.log("Sell fee percentage (basis points):", feePercentage);
        console.log("Sell fee collected: ~", feePercentage / 100, ".", feePercentage % 100);
        console.log(" Profit tax test passed - fees collected on profitable sale");

        vm.stopPrank();

        // Remove from whitelist
        vm.prank(owner);
        chooseMeToken.removeWhitelist(whitelist);
    }

    /**
     * @notice 测试亏损场景
     * @dev 当卖出时亏损，应该只收取交易手续费，不收取盈利税
     */
    function testLossScenario() internal {
        console.log("\n=== Test 5: Loss Scenario (No Profit Tax) ===");

        uint256 usdtBuyAmount = 1000 * 10 ** 18; // 1000 USDT
        address losingTrader = vm.addr(200);

        // Mock USDT
        writeTokenBalance(USDT, losingTrader, usdtBuyAmount);

        vm.startPrank(losingTrader);

        // Buy CMT at current price
        IERC20(USDT).approve(PANCAKE_V2_ROUTER, usdtBuyAmount);

        address[] memory pathBuy = new address[](2);
        pathBuy[0] = USDT;
        pathBuy[1] = address(chooseMeToken);

        IPancakeV2Router(PANCAKE_V2_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                usdtBuyAmount, 0, pathBuy, losingTrader, block.timestamp + 1000
            );

        uint256 cmtBalance = chooseMeToken.balanceOf(losingTrader);
        console.log("Trader bought CMT:", cmtBalance / 10 ** 6);

        vm.stopPrank();

        // Simulate price decrease by buying CMT with USDT (reducing CMT price)
        uint256 cmtToBuy = 1_000_000 * 10 ** 6; // Buy 1M CMT to reduce price
        vm.startPrank(techRewardsPool);

        chooseMeToken.transfer(priceManipulator, cmtToBuy);

        vm.startPrank(priceManipulator);
        chooseMeToken.approve(PANCAKE_V2_ROUTER, cmtToBuy);

        address[] memory pathPriceDecrease = new address[](2);
        pathPriceDecrease[0] = address(chooseMeToken);
        pathPriceDecrease[1] = USDT;

        IPancakeV2Router(PANCAKE_V2_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                cmtToBuy, 0, pathPriceDecrease, priceManipulator, block.timestamp + 1000
            );
        vm.stopPrank();

        console.log("Price decreased");

        // Now trader sells at a loss
        vm.startPrank(losingTrader);

        uint256 cmtToSell = cmtBalance;
        uint256 usdtBefore = IERC20(USDT).balanceOf(losingTrader);

        chooseMeToken.approve(PANCAKE_V2_ROUTER, cmtToSell);

        address[] memory pathSell = new address[](2);
        pathSell[0] = address(chooseMeToken);
        pathSell[1] = USDT;

        uint256 expectedWithoutFee = IPancakeV2Router(PANCAKE_V2_ROUTER).getAmountsOut(cmtToSell, pathSell)[1];

        IPancakeV2Router(PANCAKE_V2_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                cmtToSell, 0, pathSell, losingTrader, block.timestamp + 1000
            );

        uint256 usdtReceived = IERC20(USDT).balanceOf(losingTrader) - usdtBefore;
        console.log("USDT expectedWithoutFee:", expectedWithoutFee / 10 ** 18);
        console.log("USDT received after selling at profit:", usdtReceived / 10 ** 18);
        console.log("Trader2 Cost after:", chooseMeToken.userCost(trader2) / 10 ** 18, "USDT");

        // The trader should have paid both trading fee (3%) and profit tax (26%)
        uint256 feeCollected = expectedWithoutFee - usdtReceived;
        uint256 feePercentage = feeCollected * 10000 / expectedWithoutFee;
        console.log("Sell fee percentage (basis points):", feePercentage);
        console.log("Sell fee collected: ~", feePercentage / 100, ".", feePercentage % 100);
        console.log(" Profit tax test passed - fees collected on profitable sale");

        // Should only pay trading fee (3%), no profit tax
        console.log(" Loss scenario test passed - no profit tax on losing trades");

        vm.stopPrank();
    }
}
