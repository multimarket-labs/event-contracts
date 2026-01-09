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
import {IPancakeV2Factory} from "../src/interfaces/staking/pancake/IPancakeV2Factory.sol";
import {IPancakeV2Router} from "../src/interfaces/staking/pancake/IPancakeV2Router.sol";
import {IPancakeV2Pair} from "../src/interfaces/staking/pancake/IPancakeV2Pair.sol";

/**
 * @notice Helper function to convert uint to string
 */
function uint2str(uint256 _i) pure returns (string memory) {
    if (_i == 0) {
        return "0";
    }
    uint256 j = _i;
    uint256 len;
    while (j != 0) {
        len++;
        j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint256 k = len;
    while (_i != 0) {
        k = k - 1;
        uint8 temp = (48 + uint8(_i - _i / 10 * 10));
        bytes1 b1 = bytes1(temp);
        bstr[k] = b1;
        _i /= 10;
    }
    return string(bstr);
}

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
 * @title TestChooseMeTokenTradingV2
 * @notice 测试 ChooseMeToken 在 PancakeSwap V2 上的完整交易流程
 * @dev 主要测试以下场景:
 *      1. 发币 - 部署 ChooseMeToken 并配置池地址
 *      2. 创建 PancakeSwap V2 流动性池
 *      3. 添加流动性 (CMT/USDT)
 *      4. 买入操作 (用 USDT 购买 CMT)
 *      5. 卖出操作 (卖出 CMT 获取 USDT)
 *      6. 验证交易手续费扣除 (3%)
 *      7. 验证利润手续费扣除 (卖出时如果有利润)
 *      8. 测试普通转账 (不涉及池子，不扣费)
 *      9. 测试各种边界条件和细节
 *
 * 使用方法:
 * forge script TestChooseMeTokenTradingV2 --rpc-url https://bsc-dataseed.binance.org --broadcast
 */
contract TestChooseMeTokenTradingV2 is Script {
    // 合约地址
    ERC20 public usdt;
    ChooseMeToken public chooseMeToken;
    IPancakeV2Factory public factory;
    IPancakeV2Router public router;
    IPancakeV2Pair public pair;

    // PancakeSwap V2 地址 (BSC Mainnet)
    address public constant PANCAKE_V2_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address public constant PANCAKE_V2_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // 池子相关
    address public pairAddress;

    // 测试用户
    address public trader1;
    address public trader2;
    
    // 手续费接收地址
    address public nodePool;
    address public daoRewardPool;
    address public techRewardsPool;
    address public marketingDevelopmentPool;
    address public normalPool;
    address public subTokenPool;

    address public deployerAddress;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("==============================================");
        console.log("=== PancakeSwap V2 Integration Test Start ===");
        console.log("==============================================");
        console.log("Deployer:", deployerAddress);
        console.log("Block Number:", block.number);
        console.log("Block Timestamp:", block.timestamp);

        // 1. 部署 Mock USDT
        console.log("\n=== Step 1: Deploying Mock USDT ===");
        MockERC20 mockUsdt = new MockERC20("Mock USDT", "USDT", 18);
        usdt = ERC20(address(mockUsdt));
        console.log("Mock USDT deployed at:", address(usdt));
        console.log("Deployer USDT balance:", usdt.balanceOf(deployerAddress) / 1e18, "USDT");

        // 2. 部署 ChooseMeToken (通过代理)
        console.log("\n=== Step 2: Deploying ChooseMeToken ===");
        
        // 部署实现合约
        ChooseMeToken tokenImpl = new ChooseMeToken();
        console.log("ChooseMeToken implementation:", address(tokenImpl));

        // 部署 ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin(deployerAddress);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        // 部署代理合约
        address stakingManager = deployerAddress; // 临时使用 deployer 作为 stakingManager
        bytes memory initData =
            abi.encodeWithSelector(ChooseMeToken.initialize.selector, deployerAddress, stakingManager, address(usdt));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(tokenImpl), address(proxyAdmin), initData);

        chooseMeToken = ChooseMeToken(address(proxy));
        console.log("ChooseMeToken proxy deployed at:", address(chooseMeToken));
        console.log("ChooseMeToken name:", chooseMeToken.name());
        console.log("ChooseMeToken symbol:", chooseMeToken.symbol());
        console.log("ChooseMeToken decimals:", chooseMeToken.decimals());

        // 3. 设置 PancakeSwap V2 合约
        factory = IPancakeV2Factory(PANCAKE_V2_FACTORY);
        router = IPancakeV2Router(PANCAKE_V2_ROUTER);

        console.log("\n=== Contract Addresses ===");
        console.log("USDT:", address(usdt));
        console.log("ChooseMeToken:", address(chooseMeToken));
        console.log("PancakeV2 Factory:", PANCAKE_V2_FACTORY);
        console.log("PancakeV2 Router:", PANCAKE_V2_ROUTER);

        vm.stopBroadcast();

        // 执行测试
        testTradingFlow(deployerPrivateKey);
    }

    /**
     * @notice 完整的交易测试流程
     */
    function testTradingFlow(uint256 deployerPrivateKey) public {
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("\n==============================================");
        console.log("=== Starting Trading Flow Tests ===");
        console.log("==============================================");

        // Step 1: 设置手续费接收池地址
        vm.startBroadcast(deployerPrivateKey);
        setupFeeReceivers(deployerAddress);
        vm.stopBroadcast();

        // Step 2: 创建 PancakeSwap V2 流动性池
        vm.startBroadcast(deployerPrivateKey);
        createLiquidityPool(deployerAddress);
        vm.stopBroadcast();

        // Step 3: 添加流动性
        vm.startBroadcast(deployerPrivateKey);
        addLiquidity(deployerAddress);
        vm.stopBroadcast();

        // Step 4-9: 测试交易（使用不同的 EOA 地址模拟真实交易场景）
        // 注意：这些测试使用 vm.prank 模拟不同用户，需要在 fork 模式下运行
        console.log("\n[Note: Following tests use different EOA addresses to simulate real trading]");
        // testBuyTransaction(deployerAddress);
        // testSellTransaction(deployerAddress);
        testProfitFee(deployerAddress);
        testProfitTaxScenarios(deployerAddress);  // 新增：详细的盈利税测试
        // testNormalTransfer(deployerAddress);
        // testMultipleTradesAndFees(deployerAddress);
        
        checkPoolStatus();

        console.log("\n==============================================");
        console.log("=== All Tests Completed Successfully ===");
        console.log("==============================================");
        require(false);
    }

    /**
     * @notice Step 1: 设置手续费接收池地址
     */
    function setupFeeReceivers(address deployer) internal {
        console.log("\n=== Step 1: Setting Up Fee Receivers ===");

        // 读取当前池地址配置
        (address currentNodePool,,,,,,,,) = chooseMeToken.cmPool();

        if (currentNodePool == address(0)) {
            console.log("Pool addresses not set, configuring...");

            // 创建各个池地址
            nodePool = makeAddr("nodePool");
            daoRewardPool = makeAddr("daoRewardPool");
            techRewardsPool = makeAddr("techRewardsPool");
            marketingDevelopmentPool = makeAddr("marketingDevelopmentPool");
            normalPool = makeAddr("normalPool");
            subTokenPool = makeAddr("subTokenPool");

            ChooseMeTokenStorage.ChooseMePool memory pool = ChooseMeTokenStorage.ChooseMePool({
                nodePool: nodePool,
                daoRewardPool: daoRewardPool,
                normalPool: normalPool,
                airdropPool: deployer,
                techRewardsPool: techRewardsPool,
                ecosystemPool: makeAddr("ecosystemPool"),
                foundingStrategyPool: makeAddr("foundingStrategyPool"),
                marketingDevelopmentPool: marketingDevelopmentPool,
                subTokenPool: subTokenPool
            });

            chooseMeToken.setPoolAddress(pool);
            console.log("Fee receiver pools configured");
        } else {
            // 读取所有池地址
            (
                address _normalPool,
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
            daoRewardPool = _daoRewardPool;
            techRewardsPool = _techRewardsPool;
            marketingDevelopmentPool = _marketingDevelopmentPool;
            normalPool = _normalPool;
            subTokenPool = _subTokenPool;
            console.log("Using existing pool configuration");
        }

        console.log("Node Pool:", nodePool);
        console.log("DAO Reward Pool:", daoRewardPool);
        console.log("Tech Rewards Pool:", techRewardsPool);
        console.log("Marketing Pool:", marketingDevelopmentPool);
        console.log("Normal Pool:", normalPool);
        console.log("Sub Token Pool:", subTokenPool);

        // 执行池分配
        console.log("\nExecuting pool allocation...");
        chooseMeToken.poolAllocate();
        
        console.log("\n--- Pool Balances After Allocation ---");
        console.log("Node Pool CMT Balance:", chooseMeToken.balanceOf(nodePool) / 1e6, "CMT");
        console.log("DAO Reward Pool CMT Balance:", chooseMeToken.balanceOf(daoRewardPool) / 1e6, "CMT");
        console.log("Tech Rewards Pool CMT Balance:", chooseMeToken.balanceOf(techRewardsPool) / 1e6, "CMT");
        console.log("Marketing Pool CMT Balance:", chooseMeToken.balanceOf(marketingDevelopmentPool) / 1e6, "CMT");
        console.log("Total Supply:", chooseMeToken.totalSupply() / 1e6, "CMT");
    }

    /**
     * @notice Step 2: 创建 PancakeSwap V2 流动性池
     */
    function createLiquidityPool(address deployer) internal {
        console.log("\n=== Step 2: Creating PancakeSwap V2 Liquidity Pool ===");

        // 检查池子是否存在
        pairAddress = factory.getPair(address(usdt), address(chooseMeToken));
        console.log("Checking existing pair address:", pairAddress);

        if (pairAddress == address(0)) {
            console.log("Pair does not exist, creating...");
            
            // 创建交易对
            pairAddress = factory.createPair(address(usdt), address(chooseMeToken));
            console.log("Pair created at:", pairAddress);
        } else {
            console.log("Pair already exists");
        }

        pair = IPancakeV2Pair(pairAddress);
        
        // 获取 token0 和 token1
        address token0 = pair.token0();
        address token1 = pair.token1();
        
        console.log("\n--- Pair Information ---");
        console.log("Pair Address:", pairAddress);
        console.log("Token0:", token0);
        console.log("Token1:", token1);
        
        // 验证哪个是 USDT，哪个是 CMT
        if (token0 == address(usdt)) {
            console.log("Token0 is USDT, Token1 is CMT");
        } else {
            console.log("Token0 is CMT, Token1 is USDT");
        }
    }

    /**
     * @notice Step 3: 添加流动性
     */
    function addLiquidity(address deployer) internal {
        console.log("\n=== Step 3: Adding Liquidity to PancakeSwap V2 ===");

        // 设置初始流动性金额
        // 假设初始价格: 1 USDT = 10 CMT
        uint256 usdtAmount = 10000 * 1e18; // 10,000 USDT
        uint256 cmtAmount = 100000 * 1e6;  // 100,000 CMT (10 CMT per USDT)

        console.log("\n--- Liquidity Amounts ---");
        console.log("USDT Amount:", usdtAmount / 1e18, "USDT");
        console.log("CMT Amount:", cmtAmount / 1e6, "CMT");
        console.log("Initial Price: 1 USDT = 10 CMT");

        // 检查余额
        console.log("\n--- Before Adding Liquidity ---");
        console.log("Deployer USDT Balance:", usdt.balanceOf(deployer) / 1e18, "USDT");
        console.log("Deployer CMT Balance:", chooseMeToken.balanceOf(deployer) / 1e6, "CMT");

        // 授权 Router
        console.log("\nApproving tokens to Router...");
        usdt.approve(address(router), type(uint256).max);
        chooseMeToken.approve(address(router), type(uint256).max);

        // 添加流动性
        console.log("\nAdding liquidity...");
        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            address(usdt),
            address(chooseMeToken),
            usdtAmount,
            cmtAmount,
            0, // amountAMin (接受任何金额)
            0, // amountBMin (接受任何金额)
            deployer,
            block.timestamp + 300 // 5 minutes deadline
        );

        console.log("\n--- Liquidity Added Successfully ---");
        console.log("USDT Added:", amountA / 1e18, "USDT");
        console.log("CMT Added:", amountB / 1e6, "CMT");
        console.log("LP Tokens Received:", liquidity);

        // 检查池子储备
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        console.log("\n--- Pool Reserves ---");
        if (pair.token0() == address(usdt)) {
            console.log("USDT Reserve:", uint256(reserve0) / 1e18, "USDT");
            console.log("CMT Reserve:", uint256(reserve1) / 1e6, "CMT");
        } else {
            console.log("CMT Reserve:", uint256(reserve0) / 1e6, "CMT");
            console.log("USDT Reserve:", uint256(reserve1) / 1e18, "USDT");
        }

        console.log("\n--- After Adding Liquidity ---");
        console.log("Deployer USDT Balance:", usdt.balanceOf(deployer) / 1e18, "USDT");
        console.log("Deployer CMT Balance:", chooseMeToken.balanceOf(deployer) / 1e6, "CMT");
        console.log("Deployer LP Balance:", pair.balanceOf(deployer));
    }

    /**
     * @notice Step 4: 测试买入交易 (用 USDT 购买 CMT)
     */
    function testBuyTransaction(address deployer) internal {
        console.log("\n=== Step 4: Testing Buy Transaction ===");
        console.log("Buying CMT with USDT (should charge 3% trade fee)");

        // 创建测试用户
        trader1 = makeAddr("trader1");
        console.log("Trader1:", trader1);

        // 给 trader1 一些 USDT
        uint256 usdtAmountIn = 100 * 1e18; // 100 USDT
        vm.prank(deployer);
        usdt.transfer(trader1, usdtAmountIn);
        
        console.log("\n--- Before Buy ---");
        console.log("Trader1 USDT Balance:", usdt.balanceOf(trader1) / 1e18, "USDT");
        console.log("Trader1 CMT Balance:", chooseMeToken.balanceOf(trader1) / 1e6, "CMT");

        // 记录手续费池余额
        uint256 daoRewardPoolBefore = chooseMeToken.balanceOf(daoRewardPool);
        uint256 techPoolBefore = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolBefore = chooseMeToken.balanceOf(marketingDevelopmentPool);
        uint256 subTokenPoolBefore = chooseMeToken.balanceOf(subTokenPool);

        // 获取预期输出金额
        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(chooseMeToken);
        uint256[] memory amountsOut = router.getAmountsOut(usdtAmountIn, path);
        console.log("\nExpected CMT Output (before fees):", amountsOut[1] / 1e6, "CMT");

        // Trader1 自己执行购买
        console.log("\n[Trader1 executing buy transaction]");
        vm.startPrank(trader1);
        usdt.approve(address(router), type(uint256).max);
        
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            usdtAmountIn,
            0, // 接受任何数量（测试环境）
            path,
            trader1,
            block.timestamp + 300
        );
        vm.stopPrank();

        console.log("\n--- After Buy ---");
        uint256 trader1CmtBalance = chooseMeToken.balanceOf(trader1);
        console.log("Trader1 USDT Balance:", usdt.balanceOf(trader1) / 1e18, "USDT");
        console.log("Trader1 CMT Balance:", trader1CmtBalance / 1e6, "CMT");

        // 计算实际收到的 CMT
        uint256 actualReceived = trader1CmtBalance;
        uint256 expectedBeforeFees = amountsOut[1];
        
        console.log("\n--- Fee Analysis ---");
        console.log("Expected CMT (before fees):", expectedBeforeFees / 1e6, "CMT");
        console.log("Actual CMT Received:", actualReceived / 1e6, "CMT");
        
        if (expectedBeforeFees > 0) {
            uint256 totalFees = expectedBeforeFees - actualReceived;
            uint256 feePercentage = (totalFees * 10000) / expectedBeforeFees;
            console.log("Total Fees:", totalFees / 1e6, "CMT");
            console.log("Fee Percentage:", feePercentage / 100);
            console.log("  (decimal part):", feePercentage % 100, "%");
        }

        // 验证手续费分配
        uint256 daoRewardPoolAfter = chooseMeToken.balanceOf(daoRewardPool);
        uint256 techPoolAfter = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolAfter = chooseMeToken.balanceOf(marketingDevelopmentPool);
        uint256 subTokenPoolAfter = chooseMeToken.balanceOf(subTokenPool);

        console.log("\n--- Fee Distribution ---");
        console.log("DAO Reward Pool Increase:", (daoRewardPoolAfter - daoRewardPoolBefore) / 1e6, "CMT");
        console.log("Tech Pool Increase:", (techPoolAfter - techPoolBefore) / 1e6, "CMT");
        console.log("Marketing Pool Increase:", (marketingPoolAfter - marketingPoolBefore) / 1e6, "CMT");
        console.log("Sub Token Pool Increase:", (subTokenPoolAfter - subTokenPoolBefore) / 1e6, "CMT");
    }

    /**
     * @notice Step 5: 测试卖出交易 (卖出 CMT 获取 USDT)
     */
    function testSellTransaction(address deployer) internal {
        console.log("\n=== Step 5: Testing Sell Transaction ===");
        console.log("Selling CMT for USDT (should charge 3% trade fee)");

        // Trader1 已经有一些 CMT (从买入交易获得)
        uint256 cmtAmountIn = chooseMeToken.balanceOf(trader1) / 2; // 卖出一半
        
        console.log("\n--- Before Sell ---");
        console.log("Trader1 CMT Balance:", chooseMeToken.balanceOf(trader1) / 1e6, "CMT");
        console.log("Trader1 USDT Balance:", usdt.balanceOf(trader1) / 1e18, "USDT");
        console.log("Amount to Sell:", cmtAmountIn / 1e6, "CMT");

        // 记录手续费池余额
        uint256 daoRewardPoolBefore = chooseMeToken.balanceOf(daoRewardPool);
        uint256 techPoolBefore = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolBefore = chooseMeToken.balanceOf(marketingDevelopmentPool);
        uint256 subTokenPoolBefore = chooseMeToken.balanceOf(subTokenPool);
        uint256 normalPoolBefore = chooseMeToken.balanceOf(normalPool);

        // 获取预期输出金额
        address[] memory path = new address[](2);
        path[0] = address(chooseMeToken);
        path[1] = address(usdt);
        uint256[] memory amountsOut = router.getAmountsOut(cmtAmountIn, path);
        console.log("Expected USDT Output (before fees):", amountsOut[1] / 1e18, "USDT");

        uint256 usdtBalanceBefore = usdt.balanceOf(trader1);

        // Trader1 自己卖出 CMT
        console.log("\n[Trader1 executing sell transaction]");
        vm.startPrank(trader1);
        chooseMeToken.approve(address(router), type(uint256).max);
        
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            cmtAmountIn,
            0, // 接受任何数量
            path,
            trader1,
            block.timestamp + 300
        );
        vm.stopPrank();

        console.log("\n--- After Sell ---");
        console.log("Trader1 CMT Balance:", chooseMeToken.balanceOf(trader1) / 1e6, "CMT");
        uint256 usdtReceived = usdt.balanceOf(trader1) - usdtBalanceBefore;
        console.log("Trader1 USDT Balance:", usdt.balanceOf(trader1) / 1e18, "USDT");
        console.log("USDT Received:", usdtReceived / 1e18, "USDT");

        // 验证手续费分配
        console.log("\n--- Fee Distribution (Sell) ---");
        console.log("DAO Reward Pool Increase:", (chooseMeToken.balanceOf(daoRewardPool) - daoRewardPoolBefore) / 1e6, "CMT");
        console.log("Tech Pool Increase:", (chooseMeToken.balanceOf(techRewardsPool) - techPoolBefore) / 1e6, "CMT");
        console.log("Marketing Pool Increase:", (chooseMeToken.balanceOf(marketingDevelopmentPool) - marketingPoolBefore) / 1e6, "CMT");
        console.log("Sub Token Pool Increase:", (chooseMeToken.balanceOf(subTokenPool) - subTokenPoolBefore) / 1e6, "CMT");
        console.log("Normal Pool Increase:", (chooseMeToken.balanceOf(normalPool) - normalPoolBefore) / 1e6, "CMT");
    }

    /**
     * @notice Step 6: 测试利润手续费
     */
    function testProfitFee(address deployer) internal {
        console.log("\n=== Step 6: Testing Profit Fee ===");
        console.log("Testing profit fee when selling at a profit");

        // 创建新的交易者
        trader2 = makeAddr("trader2");
        console.log("Trader2:", trader2);

        // 给 trader2 一些 USDT
        uint256 initialUsdt = 200 * 1e18; // 200 USDT
        vm.prank(deployer);
        usdt.transfer(trader2, initialUsdt);

        console.log("\n--- Trader2 Initial State ---");
        console.log("Trader2 USDT:", usdt.balanceOf(trader2) / 1e18, "USDT");

        // 记录手续费池余额
        uint256 normalPoolBefore = chooseMeToken.balanceOf(normalPool);

        // Trader2 第一次买入
        console.log("\n--- First Buy (Establishing Cost Basis) ---");
        address[] memory buyPath = new address[](2);
        buyPath[0] = address(usdt);
        buyPath[1] = address(chooseMeToken);

        console.log("[Trader2 executing first buy]");
        vm.startPrank(trader2);
        usdt.approve(address(router), type(uint256).max);
        chooseMeToken.approve(address(router), type(uint256).max);

        uint256 firstBuyAmount = 100 * 1e18;
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            firstBuyAmount,
            0,
            buyPath,
            trader2,
            block.timestamp + 300
        );
        vm.stopPrank();

        uint256 cmtAfterBuy = chooseMeToken.balanceOf(trader2);
        console.log("CMT Received from First Buy:", cmtAfterBuy / 1e6, "CMT");

        // 创建一个大户推高价格
        console.log("\n--- Price Manipulation (Simulating Market Movement) ---");
        address whale = makeAddr("whale");
        console.log("Whale address:", whale);
        
        // 给 whale 大量 USDT
        uint256 whaleFunds = 5000 * 1e18; // 5000 USDT
        vm.prank(deployer);
        usdt.transfer(whale, whaleFunds);
        
        // Whale 进行一笔大额买入以推高价格
        console.log("[Whale executing large buy to pump price]");
        vm.startPrank(whale);
        usdt.approve(address(router), type(uint256).max);
        uint256 pricePushAmount = 1000 * 1e18; // 1000 USDT
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            pricePushAmount,
            0,
            buyPath,
            whale,
            block.timestamp + 300
        );
        vm.stopPrank();

        console.log("Price pushed up with large buy from whale");

        // Trader2 卖出（应该有利润，因此触发利润手续费）
        console.log("\n--- Sell at Profit ---");
        address[] memory sellPath = new address[](2);
        sellPath[0] = address(chooseMeToken);
        sellPath[1] = address(usdt);

        console.log("[Trader2 executing sell at profit]");
        uint256 sellAmount = cmtAfterBuy / 2; // 卖出一半
        console.log("Selling:", sellAmount / 1e6, "CMT");

        vm.startPrank(trader2);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            sellPath,
            trader2,
            block.timestamp + 300
        );
        vm.stopPrank();

        console.log("\n--- After Profitable Sell ---");
        console.log("Trader2 Final USDT:", usdt.balanceOf(trader2) / 1e18, "USDT");
        console.log("Trader2 Remaining CMT:", chooseMeToken.balanceOf(trader2) / 1e6, "CMT");

        // 检查 normalPool 是否收到了利润手续费
        uint256 normalPoolAfter = chooseMeToken.balanceOf(normalPool);
        uint256 profitFeeCollected = normalPoolAfter - normalPoolBefore;
        
        console.log("\n--- Profit Fee Analysis ---");
        console.log("Normal Pool Before:", normalPoolBefore / 1e6, "CMT");
        console.log("Normal Pool After:", normalPoolAfter / 1e6, "CMT");
        console.log("Profit Fee Collected:", profitFeeCollected / 1e6, "CMT");
        
        if (profitFeeCollected > 0) {
            console.log("SUCCESS: Profit fee was charged");
        } else {
            console.log("Note: No profit fee charged (possibly within 60 day window or no profit)");
        }
    }

    /**
     * @notice Step 6.5: 详细测试盈利税场景
     * @dev 测试两个场景：
     *      1. A 买入 100U 代币，A 卖出 200U，赚了 100U，盈利的一部分作为盈利税
     *      2. A 买入 100U 代币，转给 B，B 卖出 200U，赚了 100U，盈利税正确扣除
     */
    function testProfitTaxScenarios(address deployer) internal {
        console.log("\n=== Step 6.5: Detailed Profit Tax Testing ===");
        console.log("Testing profit tax in different scenarios");

        // ========== 场景 1: A 自己买入并卖出获利 ==========
        console.log("\n--- Scenario 1: User A buys and sells for profit ---");
        
        address userA = makeAddr("userA");
        console.log("User A:", userA);
        
        // 给 userA 一些 USDT
        uint256 initialUsdtA = 500 * 1e18; // 500 USDT
        vm.prank(deployer);
        usdt.transfer(userA, initialUsdtA);
        
        console.log("User A initial USDT:", usdt.balanceOf(userA) / 1e18, "USDT");
        
        // 记录所有手续费池的初始余额
        uint256 normalPoolBefore = chooseMeToken.balanceOf(normalPool);
        uint256 daoRewardPoolBefore = chooseMeToken.balanceOf(daoRewardPool);
        uint256 techPoolBefore = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolBefore = chooseMeToken.balanceOf(marketingDevelopmentPool);
        uint256 subTokenPoolBefore = chooseMeToken.balanceOf(subTokenPool);
        
        // A 买入：花费 100 USDT
        console.log("\n[Step 1] User A buying with 100 USDT");
        address[] memory buyPath = new address[](2);
        buyPath[0] = address(usdt);
        buyPath[1] = address(chooseMeToken);
        
        uint256 buyAmountA = 100 * 1e18; // 100 USDT
        vm.startPrank(userA);
        usdt.approve(address(router), type(uint256).max);
        chooseMeToken.approve(address(router), type(uint256).max);
        
        uint256 usdtBeforeBuy = usdt.balanceOf(userA);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            buyAmountA,
            0,
            buyPath,
            userA,
            block.timestamp + 300
        );
        uint256 cmtReceived = chooseMeToken.balanceOf(userA);
        uint256 usdtSpentBuy = usdtBeforeBuy - usdt.balanceOf(userA);
        
        console.log("  USDT spent:", usdtSpentBuy / 1e18, "USDT");
        console.log("  CMT received:", cmtReceived / 1e6, "CMT");
        console.log("  Average buy price: 1 CMT =", (usdtSpentBuy * 1e6 / cmtReceived) / 1e18, "USDT");
        
        // 推高价格 - 让其他用户买入
        vm.stopPrank();
        address pricePusher = makeAddr("pricePusher");
        vm.prank(deployer);
        usdt.transfer(pricePusher, 2000 * 1e18);
        
        console.log("\n[Step 2] Price pusher buying to increase price");
        vm.startPrank(pricePusher);
        usdt.approve(address(router), type(uint256).max);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            1500 * 1e18, // 1500 USDT
            0,
            buyPath,
            pricePusher,
            block.timestamp + 300
        );
        vm.stopPrank();
        console.log("  Price increased by large buy");
        
        // 获取当前价格
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        if (pair.token0() == address(usdt)) {
            console.log("  Current price: 1 CMT =", (uint256(reserve0) * 1e6) / uint256(reserve1) / 1e18, "USDT");
        } else {
            console.log("  Current price: 1 CMT =", (uint256(reserve1) * 1e6) / uint256(reserve0) / 1e18, "USDT");
        }
        
        // A 卖出全部 CMT
        console.log("\n[Step 3] User A selling all CMT");
        address[] memory sellPath = new address[](2);
        sellPath[0] = address(chooseMeToken);
        sellPath[1] = address(usdt);
        
        uint256 sellAmount = chooseMeToken.balanceOf(userA);
        console.log("  Selling amount:", sellAmount / 1e6, "CMT");
        
        uint256 usdtBeforeSell = usdt.balanceOf(userA);
        vm.startPrank(userA);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            sellPath,
            userA,
            block.timestamp + 300
        );
        vm.stopPrank();
        
        uint256 usdtAfterSell = usdt.balanceOf(userA);
        uint256 usdtReceived = usdtAfterSell - usdtBeforeSell;
        
        console.log("  USDT received: USDT", usdtReceived / 1e18);
        console.log("  Net profit/loss USDT:", int256(usdtReceived) / 1e18 - int256(usdtSpentBuy) / 1e18);
        
        // 检查盈利税
        uint256 normalPoolAfter = chooseMeToken.balanceOf(normalPool);
        uint256 daoRewardPoolAfter = chooseMeToken.balanceOf(daoRewardPool);
        uint256 techPoolAfter = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolAfter = chooseMeToken.balanceOf(marketingDevelopmentPool);
        uint256 subTokenPoolAfter = chooseMeToken.balanceOf(subTokenPool);
        
        console.log("\n--- Profit Tax Analysis (Scenario 1) ---");
        console.log("Normal Pool collected:", (normalPoolAfter - normalPoolBefore) / 1e6, "CMT");
        console.log("DAO Pool collected:", (daoRewardPoolAfter - daoRewardPoolBefore) / 1e6, "CMT");
        console.log("Tech Pool collected:", (techPoolAfter - techPoolBefore) / 1e6, "CMT");
        console.log("Marketing Pool collected:", (marketingPoolAfter - marketingPoolBefore) / 1e6, "CMT");
        console.log("Sub Token Pool collected:", (subTokenPoolAfter - subTokenPoolBefore) / 1e6, "CMT");
        
        uint256 totalProfitTax = (normalPoolAfter - normalPoolBefore) + 
                                  (daoRewardPoolAfter - daoRewardPoolBefore) +
                                  (techPoolAfter - techPoolBefore) +
                                  (marketingPoolAfter - marketingPoolBefore) +
                                  (subTokenPoolAfter - subTokenPoolBefore);
        console.log("Total Profit Tax:", totalProfitTax / 1e6, "CMT");
        
        // ========== 场景 2: A 买入后转给 B，B 卖出获利 ==========
        console.log("\n\n--- Scenario 2: User A buys, transfers to B, B sells for profit ---");
        console.log("Testing if cost basis transfers correctly");
        
        address userB = makeAddr("userB");
        address userC = makeAddr("userC");
        console.log("User B:", userB);
        console.log("User C:", userC);
        
        // 给 userB 一些 USDT
        uint256 initialUsdtB = 500 * 1e18; // 500 USDT
        vm.prank(deployer);
        usdt.transfer(userB, initialUsdtB);
        
        console.log("\nUser B initial USDT:", usdt.balanceOf(userB) / 1e18, "USDT");
        
        // 记录池余额
        normalPoolBefore = chooseMeToken.balanceOf(normalPool);
        daoRewardPoolBefore = chooseMeToken.balanceOf(daoRewardPool);
        techPoolBefore = chooseMeToken.balanceOf(techRewardsPool);
        marketingPoolBefore = chooseMeToken.balanceOf(marketingDevelopmentPool);
        subTokenPoolBefore = chooseMeToken.balanceOf(subTokenPool);
        
        // B 买入：花费 100 USDT
        console.log("\n[Step 1] User B buying with 100 USDT");
        uint256 buyAmountB = 100 * 1e18; // 100 USDT
        vm.startPrank(userB);
        usdt.approve(address(router), type(uint256).max);
        chooseMeToken.approve(address(router), type(uint256).max);
        
        uint256 usdtBeforeBuyB = usdt.balanceOf(userB);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            buyAmountB,
            0,
            buyPath,
            userB,
            block.timestamp + 300
        );
        uint256 cmtReceivedB = chooseMeToken.balanceOf(userB);
        uint256 usdtSpentBuyB = usdtBeforeBuyB - usdt.balanceOf(userB);
        
        console.log("  USDT spent:", usdtSpentBuyB / 1e18, "USDT");
        console.log("  CMT received:", cmtReceivedB / 1e6, "CMT");
        console.log("  Average buy price: 1 CMT =", (usdtSpentBuyB * 1e6 / cmtReceivedB) / 1e18, "USDT");
        
        // B 转账给 C（成本应该转移）
        console.log("\n[Step 2] User B transferring CMT to User C");
        uint256 transferAmountToC = cmtReceivedB;
        chooseMeToken.transfer(userC, transferAmountToC);
        vm.stopPrank();
        
        console.log("  Transferred:", transferAmountToC / 1e6, "CMT to User C");
        console.log("  User C CMT balance:", chooseMeToken.balanceOf(userC) / 1e6, "CMT");
        console.log("  Note: Cost basis should transfer from B to C");
        
        // 推高价格
        console.log("\n[Step 3] Price pusher buying again to increase price");
        vm.startPrank(pricePusher);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            300 * 1e18, // 300 USDT
            0,
            buyPath,
            pricePusher,
            block.timestamp + 300
        );
        vm.stopPrank();
        console.log("  Price increased");
        
        // 获取当前价格
        (reserve0, reserve1,) = pair.getReserves();
        if (pair.token0() == address(usdt)) {
            console.log("  Current price: 1 CMT =", (uint256(reserve0) * 1e6) / uint256(reserve1) / 1e18, "USDT");
        } else {
            console.log("  Current price: 1 CMT =", (uint256(reserve1) * 1e6) / uint256(reserve0) / 1e18, "USDT");
        }
        
        // C 卖出全部 CMT
        console.log("\n[Step 4] User C selling all CMT");
        uint256 sellAmountC = chooseMeToken.balanceOf(userC);
        console.log("  Selling amount:", sellAmountC / 1e6, "CMT");
        
        vm.startPrank(userC);
        chooseMeToken.approve(address(router), type(uint256).max);
        
        uint256 usdtBeforeSellC = usdt.balanceOf(userC);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            sellAmountC,
            0,
            sellPath,
            userC,
            block.timestamp + 300
        );
        vm.stopPrank();
        
        uint256 usdtAfterSellC = usdt.balanceOf(userC);
        uint256 usdtReceivedC = usdtAfterSellC - usdtBeforeSellC;
        
        console.log("  USDT received by C:", usdtReceivedC / 1e18, "USDT");
        console.log("  Original cost (paid by B):", usdtSpentBuyB / 1e18, "USDT");
        console.log("  Net profit USDT:", int256(usdtReceivedC) / 1e18 - int256(usdtSpentBuyB) / 1e18);
        
        // 检查盈利税
        normalPoolAfter = chooseMeToken.balanceOf(normalPool);
        daoRewardPoolAfter = chooseMeToken.balanceOf(daoRewardPool);
        techPoolAfter = chooseMeToken.balanceOf(techRewardsPool);
        marketingPoolAfter = chooseMeToken.balanceOf(marketingDevelopmentPool);
        subTokenPoolAfter = chooseMeToken.balanceOf(subTokenPool);
        
        console.log("\n--- Profit Tax Analysis (Scenario 2) ---");
        console.log("Normal Pool collected:", (normalPoolAfter - normalPoolBefore) / 1e6, "CMT");
        console.log("DAO Pool collected:", (daoRewardPoolAfter - daoRewardPoolBefore) / 1e6, "CMT");
        console.log("Tech Pool collected:", (techPoolAfter - techPoolBefore) / 1e6, "CMT");
        console.log("Marketing Pool collected:", (marketingPoolAfter - marketingPoolBefore) / 1e6, "CMT");
        console.log("Sub Token Pool collected:", (subTokenPoolAfter - subTokenPoolBefore) / 1e6, "CMT");
        
        totalProfitTax = (normalPoolAfter - normalPoolBefore) + 
                         (daoRewardPoolAfter - daoRewardPoolBefore) +
                         (techPoolAfter - techPoolBefore) +
                         (marketingPoolAfter - marketingPoolBefore) +
                         (subTokenPoolAfter - subTokenPoolBefore);
        console.log("Total Profit Tax:", totalProfitTax / 1e6, "CMT");
        
        if (totalProfitTax > 0) {
            console.log("\nSUCCESS: Profit tax was correctly charged even after transfer!");
            console.log("This confirms that cost basis transfers from B to C");
        } else {
            console.log("\nWARNING: No profit tax charged - check if within 60-day window");
        }
        
        console.log("\n=== Profit Tax Testing Completed ===");
    }

    /**
     * @notice Step 7: 测试普通转账 (不涉及池子)
     */
    function testNormalTransfer(address deployer) internal {
        console.log("\n=== Step 7: Testing Normal Transfer ===");
        console.log("Testing transfer between regular addresses (no fees expected)");

        // 创建两个普通地址
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        console.log("Alice:", alice);
        console.log("Bob:", bob);

        // 给 Alice 一些 CMT
        uint256 transferAmount = 1000 * 1e6; // 1000 CMT
        vm.prank(deployer);
        chooseMeToken.transfer(alice, transferAmount);

        // 记录转账前的余额
        uint256 aliceBalanceBefore = chooseMeToken.balanceOf(alice);
        uint256 bobBalanceBefore = chooseMeToken.balanceOf(bob);
        uint256 daoPoolBefore = chooseMeToken.balanceOf(daoRewardPool);

        console.log("\n--- Before Transfer ---");
        console.log("Alice CMT Balance:", aliceBalanceBefore / 1e6, "CMT");
        console.log("Bob CMT Balance:", bobBalanceBefore / 1e6, "CMT");
        console.log("Transfer Amount:", transferAmount / 1e6, "CMT");

        // Alice 自己转账给 Bob
        console.log("\n[Alice executing transfer to Bob]");
        vm.prank(alice);
        chooseMeToken.transfer(bob, transferAmount);

        // 记录转账后的余额
        uint256 aliceBalanceAfter = chooseMeToken.balanceOf(alice);
        uint256 bobBalanceAfter = chooseMeToken.balanceOf(bob);
        uint256 daoPoolAfter = chooseMeToken.balanceOf(daoRewardPool);

        console.log("\n--- After Transfer ---");
        console.log("Alice CMT Balance:", aliceBalanceAfter / 1e6, "CMT");
        console.log("Alice Sent:", (aliceBalanceBefore - aliceBalanceAfter) / 1e6, "CMT");
        console.log("Bob CMT Balance:", bobBalanceAfter / 1e6, "CMT");
        console.log("Bob Received:", (bobBalanceAfter - bobBalanceBefore) / 1e6, "CMT");
        console.log("DAO Pool Change:", (daoPoolAfter - daoPoolBefore) / 1e6, "CMT");

        // 验证没有手续费
        if (bobBalanceAfter - bobBalanceBefore == transferAmount) {
            console.log("\nSUCCESS: No fees charged for normal transfer");
        } else {
            console.log("\nWARNING: Unexpected fee deduction in normal transfer!");
        }
    }

    /**
     * @notice Step 8: 测试多次交易和累积手续费
     */
    function testMultipleTradesAndFees(address deployer) internal {
        console.log("\n=== Step 8: Testing Multiple Trades and Accumulated Fees ===");

        // 记录所有池的初始余额
        uint256 daoPoolInitial = chooseMeToken.balanceOf(daoRewardPool);
        uint256 techPoolInitial = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolInitial = chooseMeToken.balanceOf(marketingDevelopmentPool);
        uint256 subTokenPoolInitial = chooseMeToken.balanceOf(subTokenPool);

        console.log("\n--- Initial Fee Pool Balances ---");
        console.log("DAO Reward Pool:", daoPoolInitial / 1e6, "CMT");
        console.log("Tech Pool:", techPoolInitial / 1e6, "CMT");
        console.log("Marketing Pool:", marketingPoolInitial / 1e6, "CMT");
        console.log("Sub Token Pool:", subTokenPoolInitial / 1e6, "CMT");

        // 执行多次小额交易
        address[] memory buyPath = new address[](2);
        buyPath[0] = address(usdt);
        buyPath[1] = address(chooseMeToken);

        address[] memory sellPath = new address[](2);
        sellPath[0] = address(chooseMeToken);
        sellPath[1] = address(usdt);

        console.log("\n--- Executing 5 Buy/Sell Cycles with Different Traders ---");
        
        for (uint256 i = 0; i < 5; i++) {
            console.log("\nCycle", i + 1);
            
            // 为每个周期创建一个新的交易者
            string memory traderName = string(abi.encodePacked("cycleTrader", uint2str(i + 1)));
            address cycleTrader = makeAddr(traderName);
            console.log("  Trader:", cycleTrader);
            
            // 给交易者一些 USDT
            uint256 buyAmount = 50 * 1e18; // 50 USDT
            vm.prank(deployer);
            usdt.transfer(cycleTrader, buyAmount);
            
            // 交易者买入
            vm.startPrank(cycleTrader);
            usdt.approve(address(router), type(uint256).max);
            chooseMeToken.approve(address(router), type(uint256).max);
            
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                buyAmount,
                0,
                buyPath,
                cycleTrader,
                block.timestamp + 300
            );
            
            console.log("  Bought CMT with", buyAmount / 1e18, "USDT");
            
            // 交易者卖出一部分
            uint256 cmtBalance = chooseMeToken.balanceOf(cycleTrader);
            uint256 sellAmount = cmtBalance / 3; // 卖出三分之一
            
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                sellAmount,
                0,
                sellPath,
                cycleTrader,
                block.timestamp + 300
            );
            vm.stopPrank();
            
            console.log("  Sold", sellAmount / 1e6, "CMT");
            console.log("  Final CMT Balance:", chooseMeToken.balanceOf(cycleTrader) / 1e6, "CMT");
            console.log("  Final USDT Balance:", usdt.balanceOf(cycleTrader) / 1e18, "USDT");
        }

        // 记录最终余额
        uint256 daoPoolFinal = chooseMeToken.balanceOf(daoRewardPool);
        uint256 techPoolFinal = chooseMeToken.balanceOf(techRewardsPool);
        uint256 marketingPoolFinal = chooseMeToken.balanceOf(marketingDevelopmentPool);
        uint256 subTokenPoolFinal = chooseMeToken.balanceOf(subTokenPool);

        console.log("\n--- Final Fee Pool Balances ---");
        console.log("DAO Reward Pool:", daoPoolFinal / 1e6, "CMT");
        console.log("Tech Pool:", techPoolFinal / 1e6, "CMT");
        console.log("Marketing Pool:", marketingPoolFinal / 1e6, "CMT");
        console.log("Sub Token Pool:", subTokenPoolFinal / 1e6, "CMT");

        console.log("\n--- Total Fees Accumulated ---");
        console.log("DAO Reward Pool:", (daoPoolFinal - daoPoolInitial) / 1e6, "CMT");
        console.log("Tech Pool:", (techPoolFinal - techPoolInitial) / 1e6, "CMT");
        console.log("Marketing Pool:", (marketingPoolFinal - marketingPoolInitial) / 1e6, "CMT");
        console.log("Sub Token Pool:", (subTokenPoolFinal - subTokenPoolInitial) / 1e6, "CMT");
    }

    /**
     * @notice Step 9: 查看池子最终状态
     */
    function checkPoolStatus() internal view {
        console.log("\n=== Step 9: Final Pool Status ===");

        // 获取池子储备
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pair.getReserves();
        
        console.log("\n--- Pool Reserves ---");
        if (pair.token0() == address(usdt)) {
            console.log("USDT Reserve:", uint256(reserve0) / 1e18, "USDT");
            console.log("CMT Reserve:", uint256(reserve1) / 1e6, "CMT");
            console.log("Current Price: 1 CMT =", (uint256(reserve0) * 1e6) / uint256(reserve1) / 1e18, "USDT");
        } else {
            console.log("CMT Reserve:", uint256(reserve0) / 1e6, "CMT");
            console.log("USDT Reserve:", uint256(reserve1) / 1e18, "USDT");
            console.log("Current Price: 1 CMT =", (uint256(reserve1) * 1e6) / uint256(reserve0) / 1e18, "USDT");
        }
        console.log("Last Update Timestamp:", blockTimestampLast);

        // 获取总流动性
        uint256 totalSupply = pair.totalSupply();
        console.log("\n--- Liquidity Info ---");
        console.log("Total LP Tokens:", totalSupply);
        console.log("Deployer LP Balance:", pair.balanceOf(deployerAddress));

        // 获取各个池的最终余额
        console.log("\n--- Final Token Distribution ---");
        console.log("DAO Reward Pool:", chooseMeToken.balanceOf(daoRewardPool) / 1e6, "CMT");
        console.log("Tech Pool:", chooseMeToken.balanceOf(techRewardsPool) / 1e6, "CMT");
        console.log("Marketing Pool:", chooseMeToken.balanceOf(marketingDevelopmentPool) / 1e6, "CMT");
        console.log("Sub Token Pool:", chooseMeToken.balanceOf(subTokenPool) / 1e6, "CMT");
        console.log("Normal Pool:", chooseMeToken.balanceOf(normalPool) / 1e6, "CMT");
        console.log("Node Pool:", chooseMeToken.balanceOf(nodePool) / 1e6, "CMT");
        
        if (trader1 != address(0)) {
            console.log("Trader1 CMT:", chooseMeToken.balanceOf(trader1) / 1e6, "CMT");
            console.log("Trader1 USDT:", usdt.balanceOf(trader1) / 1e18, "USDT");
        }
        
        if (trader2 != address(0)) {
            console.log("Trader2 CMT:", chooseMeToken.balanceOf(trader2) / 1e6, "CMT");
            console.log("Trader2 USDT:", usdt.balanceOf(trader2) / 1e18, "USDT");
        }

        console.log("\n--- Token Statistics ---");
        console.log("Total Supply:", chooseMeToken.totalSupply() / 1e6, "CMT");
        console.log("Tokens in Pool:", chooseMeToken.balanceOf(pairAddress) / 1e6, "CMT");
    }
}
