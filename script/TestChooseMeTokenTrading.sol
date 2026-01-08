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
import {ChooseMeTokenStorage} from "../src/token/ChooseMeTokenStorage.sol";
import {IPancakeV3Pool} from "../src/interfaces/staking/pancake/IPancakeV3Pool.sol";
import {IPancakeV3Factory} from "../src/interfaces/staking/pancake/IPancakeV3Factory.sol";
import {IV3NonfungiblePositionManager} from "../src/interfaces/staking/pancake/IV3NonfungiblePositionManager.sol";
import {IV3SwapRouter} from "../src/interfaces/staking/pancake/IV3SwapRouter.sol";

/**
 * @notice Mock ERC20 token for testing
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, 1000000000 * 10 ** decimals_); // 1 billion tokens
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title TestChooseMeTokenTrading
 * @notice 测试 ChooseMeToken 的 _update 函数中的手续费扣除逻辑
 * @dev 主要测试以下场景:
 *      1. 创建流动性池
 *      2. 添加流动性
 *      3. 买入操作 (从池子买入 CMT)
 *      4. 卖出操作 (向池子卖出 CMT)
 *      5. 验证手续费分配是否正确
 *
 * 使用方法:
 * forge script TestChooseMeTokenTrading --rpc-url https://bsc-dataseed.binance.org --broadcast
 */
contract TestChooseMeTokenTrading is Script {
    // 合约地址
    ERC20 public usdt;
    ChooseMeToken public chooseMeToken;
    IPancakeV3Factory public factory;
    IV3NonfungiblePositionManager public positionManager;
    IV3SwapRouter public swapRouter;

    // PancakeSwap V3 地址 (BSC Mainnet)
    address public constant PANCAKE_V3_FACTORY = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    address public constant PANCAKE_V3_POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    address public constant PANCAKE_V3_SWAP_ROUTER = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;

    // 测试参数
    uint24 public constant POOL_FEE = 2500; // 0.25% 费率
    int24 public constant TICK_LOWER = -887200; // 必须是 50 的倍数 (tickSpacing for 0.25% fee)
    int24 public constant TICK_UPPER = 887200; // 必须是 50 的倍数

    // 池子相关
    address public poolAddress;
    uint256 public positionTokenId;

    // 测试用户
    address public trader;

    // 手续费接收地址
    address public nodePool;
    address public techRewardsPool;
    address public marketingDevelopmentPool;

    address public deployerAddress;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying Test Contracts ===");
        console.log("Deployer:", deployerAddress);

        // 1. 部署 Mock USDT
        console.log("\nDeploying Mock USDT...");
        MockERC20 mockUsdt = new MockERC20("Mock USDT", "USDT", 18);
        usdt = ERC20(address(mockUsdt));
        console.log("Mock USDT deployed at:", address(usdt));
        console.log("Deployer USDT balance:", usdt.balanceOf(deployerAddress));

        // 2. 部署 ChooseMeToken (通过代理)
        console.log("\nDeploying ChooseMeToken...");

        // 部署实现合约
        ChooseMeToken tokenImpl = new ChooseMeToken();
        console.log("ChooseMeToken implementation:", address(tokenImpl));

        // 部署 ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin(deployerAddress);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        // 部署代理合约
        address stakingManager = deployerAddress; // 临时使用 deployer 作为 stakingManager
        bytes memory initData =
            abi.encodeWithSelector(ChooseMeToken.initialize.selector, deployerAddress, stakingManager);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(tokenImpl), address(proxyAdmin), initData);

        chooseMeToken = ChooseMeToken(address(proxy));
        console.log("ChooseMeToken proxy deployed at:", address(chooseMeToken));

        // 3. 设置 PancakeSwap V3 合约
        factory = IPancakeV3Factory(PANCAKE_V3_FACTORY);
        positionManager = IV3NonfungiblePositionManager(PANCAKE_V3_POSITION_MANAGER);
        swapRouter = IV3SwapRouter(PANCAKE_V3_SWAP_ROUTER);

        console.log("\n=== Contract Addresses ===");
        console.log("USDT:", address(usdt));
        console.log("ChooseMeToken:", address(chooseMeToken));
        console.log("PancakeV3 Factory:", PANCAKE_V3_FACTORY);
        console.log("PancakeV3 PositionManager:", PANCAKE_V3_POSITION_MANAGER);

        vm.stopBroadcast();

        // 执行测试
        testTrading(deployerPrivateKey);
    }

    /**
     * @notice 完整的交易测试流程
     */
    function testTrading(uint256 deployerPrivateKey) public {
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("\n=== ChooseMeToken Trading Integration Test ===");
        console.log("Deployer:", deployerAddress);

        // Step 1: 设置手续费接收池地址 (需要 broadcast)
        vm.startBroadcast(deployerPrivateKey);
        setupFeeReceivers(deployerAddress);
        vm.stopBroadcast();

        // Step 2: 创建或获取流动性池 (需要 broadcast)
        vm.startBroadcast(deployerPrivateKey);
        setupLiquidityPool(deployerAddress);
        vm.stopBroadcast();

        // Step 3: 添加流动性 (需要 broadcast)
        vm.startBroadcast(deployerPrivateKey);
        addLiquidity(deployerAddress);
        vm.stopBroadcast();

        // Step 4-6: 测试交易（使用 vm.prank 模拟，不实际广播）
        console.log("\n=== Note: Following tests use vm.prank for simulation, not broadcasted ===");

        // Step 4: 测试买入交易（从池子到用户，应扣除手续费）
        testBuyTransaction(deployerAddress);

        // Step 5: 测试卖出交易（从用户到池子，应扣除手续费）
        testSellTransaction(deployerAddress);

        // Step 6: 测试普通转账（不涉及池子，不扣除手续费）
        testNormalTransfer(deployerAddress);

        console.log("\n=== Test Completed Successfully ===");
    }

    /**
     * @notice 设置手续费接收池地址
     */
    function setupFeeReceivers(address deployer) internal {
        console.log("\n=== Step 1: Setting Up Fee Receivers ===");

        // 设置 factory 地址
        try chooseMeToken.factory() returns (address currentFactory) {
            if (currentFactory == address(0)) {
                console.log("Setting factory address...");
                chooseMeToken.setFactory(PANCAKE_V3_FACTORY);
                console.log("Factory set to:", PANCAKE_V3_FACTORY);
            } else {
                console.log("Factory already set to:", currentFactory);
            }
        } catch {
            console.log("Setting factory address...");
            chooseMeToken.setFactory(PANCAKE_V3_FACTORY);
            console.log("Factory set to:", PANCAKE_V3_FACTORY);
        }

        // 读取当前池地址配置 - 检查 nodePool 是否已设置
        (address currentNodePool,,,,,,,) = chooseMeToken.cmPool();

        if (currentNodePool == address(0)) {
            console.log("Pool addresses not set, configuring...");

            // 创建临时地址作为各个池
            nodePool = makeAddr("nodePool");
            techRewardsPool = makeAddr("techRewardsPool");
            marketingDevelopmentPool = makeAddr("marketingDevelopmentPool");

            ChooseMeTokenStorage.chooseMePool memory pool = ChooseMeTokenStorage.chooseMePool({
                nodePool: nodePool,
                daoRewardPool: makeAddr("daoRewardPool"),
                airdropPool: deployerAddress,
                techRewardsPool: deployerAddress,
                ecosystemPool: makeAddr("ecosystemPool"),
                foundingStrategyPool: makeAddr("foundingStrategyPool"),
                marketingDevelopmentPool: marketingDevelopmentPool,
                subTokenPool: makeAddr("subTokenPool")
            });

            chooseMeToken.setPoolAddress(pool);
            console.log("Fee receiver pools configured");
        } else {
            // 读取所有池地址
            (
                address _nodePool,
                address _daoRewardPool,
                address _airdropPool,
                address _techRewardsPool,
                address _ecosystemPool,
                address _foundingStrategyPool,
                address _marketingDevelopmentPool,
                address _subTokenPool
            ) = chooseMeToken.cmPool();

            nodePool = _nodePool;
            techRewardsPool = _techRewardsPool;
            marketingDevelopmentPool = _marketingDevelopmentPool;
            console.log("Using existing pool configuration");
        }

        console.log("Node Pool:", nodePool);
        console.log("Tech Rewards Pool:", techRewardsPool);
        console.log("Marketing Pool:", marketingDevelopmentPool);

        console.log("\nExecuting pool allocation...");
        chooseMeToken.poolAllocate();
        console.log("Pool allocation completed successfully");
        console.log("Node Pool CMT Balance:", chooseMeToken.balanceOf(nodePool));
        console.log("DAO Reward Pool CMT Balance:", chooseMeToken.balanceOf(makeAddr("daoRewardPool")));
        console.log("Tech Rewards Pool CMT Balance:", chooseMeToken.balanceOf(techRewardsPool));
        console.log("Total Supply:", chooseMeToken.totalSupply());
    }

    /**
     * @notice 创建或获取流动性池
     */
    function setupLiquidityPool(address deployer) internal {
        console.log("\n=== Step 2: Setting Up Liquidity Pool ===");

        // 确定 token0 和 token1 的顺序
        (address token0, address token1) = address(usdt) < address(chooseMeToken)
            ? (address(usdt), address(chooseMeToken))
            : (address(chooseMeToken), address(usdt));

        console.log("Token0:", token0);
        console.log("Token1:", token1);

        // 检查池子是否存在
        poolAddress = factory.getPool(token0, token1, POOL_FEE);
        console.log("Pool Address:", poolAddress);

        if (poolAddress == address(0)) {
            console.log("Pool does not exist, creating...");

            // 计算初始价格: 1 USDT = 10 CMT
            uint160 sqrtPriceX96_2;
            if (token0 == address(usdt)) {
                // token0=USDT(18位), token1=CMT(6位)
                // 目标: 1 USDT (1e18单位) = 10 CMT (10e6单位)
                // price = sqrt((2^192 * 10^7) / 1e18)
                sqrtPriceX96_2 = 250541448375047931186413;
            } else {
                // token0=CMT(6位), token1=USDT(18位)
                // 目标: 1 CMT (1e6单位) = 0.1 USDT (0.1e18单位)
                // price = sqrt((2^192 * 10^18) / 1e7)
                sqrtPriceX96_2 = 25056344881171517265510420726122707;
            }

            // 创建并初始化池子
            poolAddress = positionManager.createAndInitializePoolIfNecessary(token0, token1, POOL_FEE, sqrtPriceX96_2);

            console.log("Pool created at:", poolAddress);
        } else {
            console.log("Pool already exists");
        }

        // 验证池子信息
        IPancakeV3Pool pool = IPancakeV3Pool(poolAddress);
        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();
        console.log("Pool sqrtPriceX96:", sqrtPriceX96);
        console.log("Pool tick:", uint256(uint24(tick)));
    }

    /**
     * @notice 添加流动性
     */
    function addLiquidity(address deployer) internal {
        console.log("\n=== Step 3: Adding Liquidity ===");

        // 准备流动性数量
        uint256 usdtAmount = 10000 * 1e18; // 10,000 USDT
        uint256 cmtAmount = 100000 * 1e6; // 100,000 CMT

        // 检查余额
        uint256 usdtBalanceBefore = usdt.balanceOf(deployer);
        uint256 cmtBalanceBefore = chooseMeToken.balanceOf(deployer);
        console.log("\n--- Deployer Balances Before Adding Liquidity ---");
        console.log("USDT Balance:", usdtBalanceBefore);
        console.log("CMT Balance:", cmtBalanceBefore);

        require(usdtBalanceBefore >= usdtAmount, "Insufficient USDT");
        require(cmtBalanceBefore >= cmtAmount, "Insufficient CMT");

        // 确定 token0 和 token1
        (address token0, address token1) = address(usdt) < address(chooseMeToken)
            ? (address(usdt), address(chooseMeToken))
            : (address(chooseMeToken), address(usdt));

        (uint256 amount0Desired, uint256 amount1Desired) =
            address(usdt) < address(chooseMeToken) ? (usdtAmount, cmtAmount) : (cmtAmount, usdtAmount);

        // 授权
        console.log("Approving tokens...");
        usdt.approve(address(positionManager), usdtAmount);
        chooseMeToken.approve(address(positionManager), cmtAmount);

        // 添加流动性
        IV3NonfungiblePositionManager.MintParams memory params = IV3NonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: POOL_FEE,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: deployer,
            deadline: block.timestamp + 300
        });

        console.log("minting liquidity...");
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = positionManager.mint(params);

        positionTokenId = tokenId;

        // 获取添加流动性后的余额
        uint256 usdtBalanceAfter = usdt.balanceOf(deployer);
        uint256 cmtBalanceAfter = chooseMeToken.balanceOf(deployer);

        console.log("\n--- Liquidity Added Successfully ---");
        console.log("Position Token ID:", tokenId);
        console.log("Liquidity:", liquidity);
        console.log("Amount0 Used:", amount0);
        console.log("Amount1 Used:", amount1);

        console.log("\n--- Deployer Balances After Adding Liquidity ---");
        console.log("USDT Balance:", usdtBalanceAfter);
        console.log("USDT Used:", usdtBalanceBefore - usdtBalanceAfter);
        console.log("CMT Balance:", cmtBalanceAfter);
        console.log("CMT Used:", cmtBalanceBefore - cmtBalanceAfter);
    }

    /**
     * @notice 测试买入交易 (从池子买入 CMT)
     * @dev 应该触发手续费扣除逻辑
     */
    function testBuyTransaction(address deployer) internal {
        console.log("\n=== Step 4: Testing Buy Transaction ===");
        console.log("Simulating user buying CMT from pool...");
        console.log("Pool Address:", poolAddress);

        // 创建测试买家
        address buyer = makeAddr("buyer");

        // 给买家一些 USDT
        uint256 buyAmount = 100 * 1e18; // 100 USDT
        vm.prank(deployer);
        usdt.transfer(buyer, buyAmount);

        // 记录交易前的余额
        uint256 buyerUsdtBefore = usdt.balanceOf(buyer);
        uint256 buyerCmtBefore = chooseMeToken.balanceOf(buyer);
        uint256 poolUsdtBefore = usdt.balanceOf(poolAddress);
        uint256 poolCmtBefore = chooseMeToken.balanceOf(poolAddress);
        uint256 nodePoolBalanceBefore = chooseMeToken.balanceOf(nodePool);
        uint256 techPoolBalanceBefore = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolBalanceBefore = chooseMeToken.balanceOf(marketingDevelopmentPool);

        console.log("\n--- Balances Before Buy ---");
        console.log("Buyer USDT:", buyerUsdtBefore);
        console.log("Buyer CMT:", buyerCmtBefore);
        console.log("Pool USDT:", poolUsdtBefore);
        console.log("Pool CMT:", poolCmtBefore);
        console.log("\n--- Fee Receiver Pools Before ---");
        console.log("Node Pool CMT:", nodePoolBalanceBefore);
        console.log("Tech Rewards Pool CMT:", techPoolBalanceBefore);
        console.log("Marketing Pool CMT:", marketingPoolBalanceBefore);

        // 买家授权并通过 Router 买入 CMT
        vm.startPrank(buyer);
        usdt.approve(address(swapRouter), buyAmount);

        // 使用 Router 的 exactInputSingle 进行交易
        console.log("\nExecuting swap via Router...");
        console.log("Token In: USDT");
        console.log("Token Out: CMT");
        console.log("Amount In:", buyAmount);

        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(usdt),
            tokenOut: address(chooseMeToken),
            fee: POOL_FEE,
            recipient: buyer,
            deadline: block.timestamp + 300,
            amountIn: buyAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = swapRouter.exactInputSingle(params);
        console.log("Swap executed successfully");
        console.log("Amount Out:", amountOut);

        vm.stopPrank();

        // 记录交易后的余额
        uint256 buyerUsdtAfter = usdt.balanceOf(buyer);
        uint256 buyerCmtAfter = chooseMeToken.balanceOf(buyer);
        uint256 poolUsdtAfter = usdt.balanceOf(poolAddress);
        uint256 poolCmtAfter = chooseMeToken.balanceOf(poolAddress);
        uint256 nodePoolBalanceAfter = chooseMeToken.balanceOf(nodePool);
        uint256 techPoolBalanceAfter = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolBalanceAfter = chooseMeToken.balanceOf(marketingDevelopmentPool);

        console.log("\n--- Balances After Buy ---");
        console.log("Buyer USDT:", buyerUsdtAfter);
        console.log("USDT Spent:", buyerUsdtBefore - buyerUsdtAfter);
        console.log("Buyer CMT:", buyerCmtAfter);
        console.log("CMT Received:", buyerCmtAfter - buyerCmtBefore);
        console.log("Pool USDT:", poolUsdtAfter);
        console.log("Pool USDT Gained:", poolUsdtAfter - poolUsdtBefore);
        console.log("Pool CMT:", poolCmtAfter);
        console.log("Pool CMT Sent:", poolCmtBefore - poolCmtAfter);

        // 计算交易数量
        uint256 usdtSpent = buyerUsdtBefore - buyerUsdtAfter;
        uint256 cmtReceived = buyerCmtAfter - buyerCmtBefore;
        uint256 cmtFromPool = poolCmtBefore - poolCmtAfter;

        console.log("\n--- Transaction Details ---");
        console.log("USDT Spent by Buyer:", usdtSpent);
        console.log("CMT Received by Buyer:", cmtReceived);
        console.log("CMT Sent from Pool:", cmtFromPool);

        // 计算手续费收入
        uint256 nodeFeeReceived = nodePoolBalanceAfter - nodePoolBalanceBefore;
        uint256 techFeeReceived = techPoolBalanceAfter - techPoolBalanceBefore;
        uint256 marketingFeeReceived = marketingPoolBalanceAfter - marketingPoolBalanceBefore;
        uint256 totalFeesCollected = nodeFeeReceived + techFeeReceived + marketingFeeReceived;

        console.log("\n--- Fee Receiver Pools After ---");
        console.log("Node Pool CMT:", nodePoolBalanceAfter);
        console.log("Node Pool Fee Received:", nodeFeeReceived);
        console.log("Tech Rewards Pool CMT:", techPoolBalanceAfter);
        console.log("Tech Pool Fee Received:", techFeeReceived);
        console.log("Marketing Pool CMT:", marketingPoolBalanceAfter);
        console.log("Marketing Pool Fee Received:", marketingFeeReceived);

        console.log("\n--- Fee Analysis ---");
        console.log("Total Fees Collected:", totalFeesCollected);

        // 验证手续费是否正确扣除
        if (cmtFromPool > 0) {
            // 根据 _update 函数，应该扣除:
            // nodeFee: 0.5%, clusterFee: 0.5%, marketFee: 0.5%, techFee: 1%, subFee: 0.5%
            // 总计: 3%
            uint256 feeRateBasisPoints = (totalFeesCollected * 10000) / cmtFromPool;
            uint256 feeRateInteger = feeRateBasisPoints / 100;
            uint256 feeRateDecimal = feeRateBasisPoints % 100;

            console.log("Expected Fee Rate: 3.00% (300 basis points)");
            console.log("Actual Fee Rate (basis points):", feeRateBasisPoints);
            console.log("Actual Fee Rate (integer part):", feeRateInteger);
            console.log("Actual Fee Rate (decimal part):", feeRateDecimal);
            console.log("Total Fees:", totalFeesCollected);
            console.log("CMT from Pool:", cmtFromPool);

            if (feeRateBasisPoints >= 290 && feeRateBasisPoints <= 310) {
                console.log("SUCCESS: Fee rate is within expected range (2.9% - 3.1%)");
            } else {
                console.log("WARNING: Fee rate is outside expected range!");
            }
        }
    }

    /**
     * @notice 测试卖出交易 (卖出 CMT 到池子)
     * @dev 应该触发手续费扣除逻辑
     */
    function testSellTransaction(address deployer) internal {
        console.log("\n=== Step 5: Testing Sell Transaction ===");
        console.log("Simulating user selling CMT to pool...");
        console.log("Pool Address:", poolAddress);

        // 创建测试卖家
        address seller = makeAddr("seller");

        // 给卖家一些 CMT
        uint256 sellAmount = 1000 * 1e6; // 1,000 CMT
        vm.prank(deployer);
        chooseMeToken.transfer(seller, sellAmount);

        // 记录交易前的余额
        uint256 sellerUsdtBefore = usdt.balanceOf(seller);
        uint256 sellerCmtBefore = chooseMeToken.balanceOf(seller);
        uint256 poolUsdtBefore = usdt.balanceOf(poolAddress);
        uint256 poolCmtBefore = chooseMeToken.balanceOf(poolAddress);
        uint256 nodePoolBalanceBefore = chooseMeToken.balanceOf(nodePool);
        uint256 techPoolBalanceBefore = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolBalanceBefore = chooseMeToken.balanceOf(marketingDevelopmentPool);

        console.log("\n--- Balances Before Sell ---");
        console.log("Seller USDT:", sellerUsdtBefore);
        console.log("Seller CMT:", sellerCmtBefore);
        console.log("Sell Amount:", sellAmount);
        console.log("Pool USDT:", poolUsdtBefore);
        console.log("Pool CMT:", poolCmtBefore);
        console.log("\n--- Fee Receiver Pools Before ---");
        console.log("Node Pool CMT:", nodePoolBalanceBefore);
        console.log("Tech Rewards Pool CMT:", techPoolBalanceBefore);
        console.log("Marketing Pool CMT:", marketingPoolBalanceBefore);

        // 卖家授权并通过 Router 卖出 CMT
        vm.startPrank(seller);
        chooseMeToken.approve(address(swapRouter), sellAmount);

        // 使用 Router 的 exactInputSingle 进行交易
        console.log("\nExecuting swap via Router...");
        console.log("Token In: CMT");
        console.log("Token Out: USDT");
        console.log("Amount In:", sellAmount);

        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(chooseMeToken),
            tokenOut: address(usdt),
            fee: POOL_FEE,
            recipient: seller,
            deadline: block.timestamp + 300,
            amountIn: sellAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = swapRouter.exactInputSingle(params);
        console.log("Swap executed successfully");
        console.log("Amount Out:", amountOut);

        vm.stopPrank();

        // 记录交易后的余额
        uint256 sellerUsdtAfter = usdt.balanceOf(seller);
        uint256 sellerCmtAfter = chooseMeToken.balanceOf(seller);
        uint256 poolUsdtAfter = usdt.balanceOf(poolAddress);
        uint256 poolCmtAfter = chooseMeToken.balanceOf(poolAddress);
        uint256 nodePoolBalanceAfter = chooseMeToken.balanceOf(nodePool);
        uint256 techPoolBalanceAfter = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolBalanceAfter = chooseMeToken.balanceOf(marketingDevelopmentPool);

        console.log("\n--- Balances After Sell ---");
        console.log("Seller USDT:", sellerUsdtAfter);
        console.log("USDT Gained:", sellerUsdtAfter - sellerUsdtBefore);
        console.log("Seller CMT:", sellerCmtAfter);
        console.log("CMT Spent:", sellerCmtBefore - sellerCmtAfter);
        console.log("Pool USDT:", poolUsdtAfter);
        console.log("Pool USDT Sent:", poolUsdtBefore - poolUsdtAfter);
        console.log("Pool CMT:", poolCmtAfter);
        console.log("Pool CMT Gained:", poolCmtAfter - poolCmtBefore);

        // 计算交易数量
        uint256 cmtSent = sellerCmtBefore - sellerCmtAfter;
        uint256 cmtToPool = poolCmtAfter - poolCmtBefore;
        uint256 usdtGained = sellerUsdtAfter - sellerUsdtBefore;

        console.log("\n--- Transaction Details ---");
        console.log("CMT Sent by Seller:", cmtSent);
        console.log("CMT Received by Pool:", cmtToPool);
        console.log("USDT Gained by Seller:", usdtGained);

        // 计算手续费收入
        uint256 nodeFeeReceived = nodePoolBalanceAfter - nodePoolBalanceBefore;
        uint256 techFeeReceived = techPoolBalanceAfter - techPoolBalanceBefore;
        uint256 marketingFeeReceived = marketingPoolBalanceAfter - marketingPoolBalanceBefore;
        uint256 totalFeesCollected = nodeFeeReceived + techFeeReceived + marketingFeeReceived;

        console.log("\n--- Fee Receiver Pools After ---");
        console.log("Node Pool CMT:", nodePoolBalanceAfter);
        console.log("Node Pool Fee Received:", nodeFeeReceived);
        console.log("Tech Rewards Pool CMT:", techPoolBalanceAfter);
        console.log("Tech Pool Fee Received:", techFeeReceived);
        console.log("Marketing Pool CMT:", marketingPoolBalanceAfter);
        console.log("Marketing Pool Fee Received:", marketingFeeReceived);

        console.log("\n--- Fee Analysis ---");
        console.log("Total Fees Collected:", totalFeesCollected);

        // 验证手续费是否正确扣除
        if (cmtSent > 0) {
            // 根据 _update 函数，应该扣除:
            // nodeFee: 0.5%, clusterFee: 0.5%, marketFee: 0.5%, techFee: 1%, subFee: 0.5%
            // 总计: 3%
            uint256 feeRateBasisPoints = (totalFeesCollected * 10000) / cmtSent;
            uint256 feeRateInteger = feeRateBasisPoints / 100;
            uint256 feeRateDecimal = feeRateBasisPoints % 100;

            console.log("Expected Fee Rate: 3.00% (300 basis points)");
            console.log("Actual Fee Rate (basis points):", feeRateBasisPoints);
            console.log("Actual Fee Rate (integer part):", feeRateInteger);
            console.log("Actual Fee Rate (decimal part):", feeRateDecimal);
            console.log("Total Fees:", totalFeesCollected);
            console.log("CMT Sent:", cmtSent);
            console.log("Net CMT to Pool:", cmtToPool);

            if (feeRateBasisPoints >= 290 && feeRateBasisPoints <= 310) {
                console.log("SUCCESS: Fee rate is within expected range (2.9% - 3.1%)");
            } else {
                console.log("WARNING: Fee rate is outside expected range!");
            }
        }
    }

    /**
     * @notice 测试普通转账 (不涉及池子)
     * @dev 不应该触发手续费扣除逻辑
     */
    function testNormalTransfer(address deployer) internal {
        console.log("\n=== Step 6: Testing Normal Transfer ===");
        console.log("Testing transfer between regular addresses (no fees expected)...");

        // 创建两个普通地址
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        // 给 Alice 一些 CMT
        uint256 transferAmount = 100 * 1e6; // 100 CMT
        vm.prank(deployer);
        chooseMeToken.transfer(alice, transferAmount);

        // 记录交易前的余额
        uint256 aliceBalanceBefore = chooseMeToken.balanceOf(alice);
        uint256 bobBalanceBefore = chooseMeToken.balanceOf(bob);
        uint256 nodePoolBalanceBefore = chooseMeToken.balanceOf(nodePool);
        uint256 techPoolBalanceBefore = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolBalanceBefore = chooseMeToken.balanceOf(marketingDevelopmentPool);

        console.log("\n--- Balances Before Transfer ---");
        console.log("Alice CMT:", aliceBalanceBefore);
        console.log("Transfer Amount:", transferAmount);
        console.log("Bob CMT:", bobBalanceBefore);
        console.log("Node Pool CMT:", nodePoolBalanceBefore);
        console.log("Tech Pool CMT:", techPoolBalanceBefore);
        console.log("Marketing Pool CMT:", marketingPoolBalanceBefore);

        // Alice 转账给 Bob
        vm.prank(alice);
        chooseMeToken.transfer(bob, transferAmount);

        // 记录交易后的余额
        uint256 aliceBalanceAfter = chooseMeToken.balanceOf(alice);
        uint256 bobBalanceAfter = chooseMeToken.balanceOf(bob);
        uint256 nodePoolBalanceAfter = chooseMeToken.balanceOf(nodePool);
        uint256 techPoolBalanceAfter = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolBalanceAfter = chooseMeToken.balanceOf(marketingDevelopmentPool);

        console.log("\n--- Balances After Transfer ---");
        console.log("Alice CMT:", aliceBalanceAfter);
        console.log("Alice Sent:", aliceBalanceBefore - aliceBalanceAfter);
        console.log("Bob CMT:", bobBalanceAfter);
        console.log("Bob Received:", bobBalanceAfter - bobBalanceBefore);
        
        int256 nodePoolChange = int256(nodePoolBalanceAfter) - int256(nodePoolBalanceBefore);
        console.log("Node Pool CMT:", nodePoolBalanceAfter);
        if (nodePoolChange >= 0) {
            console.log("Node Pool Change: +", uint256(nodePoolChange));
        } else {
            console.log("Node Pool Change: -", uint256(-nodePoolChange));
        }
        
        int256 techPoolChange = int256(techPoolBalanceAfter) - int256(techPoolBalanceBefore);
        console.log("Tech Pool CMT:", techPoolBalanceAfter);
        if (techPoolChange >= 0) {
            console.log("Tech Pool Change: +", uint256(techPoolChange));
        } else {
            console.log("Tech Pool Change: -", uint256(-techPoolChange));
        }
        
        int256 marketingPoolChange = int256(marketingPoolBalanceAfter) - int256(marketingPoolBalanceBefore);
        console.log("Marketing Pool CMT:", marketingPoolBalanceAfter);
        if (marketingPoolChange >= 0) {
            console.log("Marketing Pool Change: +", uint256(marketingPoolChange));
        } else {
            console.log("Marketing Pool Change: -", uint256(-marketingPoolChange));
        }

        // 验证：普通转账不应扣除手续费
        uint256 aliceSent = aliceBalanceBefore - aliceBalanceAfter;
        uint256 bobReceived = bobBalanceAfter - bobBalanceBefore;
        uint256 nodePoolFee =
            nodePoolBalanceAfter > nodePoolBalanceBefore ? nodePoolBalanceAfter - nodePoolBalanceBefore : 0;
        uint256 techPoolFee =
            techPoolBalanceAfter > techPoolBalanceBefore ? techPoolBalanceAfter - techPoolBalanceBefore : 0;
        uint256 marketingPoolFee = marketingPoolBalanceAfter > marketingPoolBalanceBefore
            ? marketingPoolBalanceAfter - marketingPoolBalanceBefore
            : 0;
        uint256 totalFees = nodePoolFee + techPoolFee + marketingPoolFee;

        console.log("\n--- Transfer Verification ---");
        console.log("Transfer Amount:", transferAmount);
        console.log("Alice Sent:", aliceSent);
        console.log("Bob Received:", bobReceived);
        console.log("Total Fees Collected:", totalFees);

        if (bobReceived == transferAmount && totalFees == 0 && aliceSent == transferAmount) {
            console.log("SUCCESS: No fees charged for normal transfer (EOA to EOA)");
            console.log("Transfer matches exactly:", transferAmount);
        } else {
            console.log("WARNING: Unexpected behavior in normal transfer!");
            console.log("Expected Bob receives:", transferAmount);
            console.log("Actual Bob received:", bobReceived);
            console.log("Expected fees: 0");
            console.log("Actual fees:", totalFees);
        }
    }
}
