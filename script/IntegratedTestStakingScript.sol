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

import {EmptyContract} from "../src/utils/EmptyContract.sol";
import {ChooseMeToken} from "../src/token/ChooseMeToken.sol";
import {ChooseMeTokenStorage} from "../src/token/ChooseMeTokenStorage.sol";
import {NodeManager} from "../src/staking/NodeManager.sol";
import {StakingManager} from "../src/staking/StakingManager.sol";
import {DaoRewardManager} from "../src/token/allocation/DaoRewardManager.sol";
import {FomoTreasureManager} from "../src/token/allocation/FomoTreasureManager.sol";
import {EventFundingManager} from "../src/staking/EventFundingManager.sol";
import {IV3NonfungiblePositionManager} from "../src/interfaces/staking/pancake/IV3NonfungiblePositionManager.sol";
import {IPancakeV3Pool} from "../src/interfaces/staking/pancake/IPancakeV3Pool.sol";
import {IPancakeV3Factory} from "../src/interfaces/staking/pancake/IPancakeV3Factory.sol";

// PancakeSwap V3 SmartRouter 接口
interface IPancakeV3SmartRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

// 使用说明:
// 1. 测试 PancakeSwap V3 添加流动性:
//    forge script IntegratedTestStakingScript --slow --multi --rpc-url https://bsc-dataseed.binance.org --broadcast
//    (需要先将 run() 中的调用改为 testAddLiquidity)
//
// 2. 测试 NodeManager 添加流动性:
//    forge script IntegratedTestStakingScript --slow --multi --rpc-url https://bsc-dataseed.binance.org --broadcast
//    (当前默认执行 testNodeAddLiquidity)
//
// 前置条件:
// - 确保 .env 文件包含 PRIVATE_KEY
// - 确保部署者账户有足够的 USDT 和 CMT 余额
// - 确保 ./out/__deployed_addresses.json 文件存在且包含所有合约地址
//
// 代币精度说明:
// - USDT: 18 位小数 (1 USDT = 1e18 最小单位)
// - CMT: 6 位小数 (1 CMT = 1e6 最小单位)
// - 目标价格: 1 USDT = 10 CMT
//
// sqrtPriceX96 计算说明:
// - 在 PancakeSwap V3 中，price = amount1 / amount0 (使用原始代币数量，包含精度)
// - sqrtPriceX96 = sqrt(price) * 2^96
// - 计算示例:
//   * 2^96 = 79228162514264337593543950336
//   * sqrt(1e-11) = 3.162277660168379e-6
//   * sqrt(1e11) = 316227.7660168379
// - 如果 token0=USDT, token1=CMT:
//   * price = (10 * 1e6) / (1 * 1e18) = 1e-11
//   * sqrtPriceX96 = sqrt(1e-11) * 2^96 ≈ 250541448375048
// - 如果 token0=CMT, token1=USDT:
//   * price = (0.1 * 1e18) / (1 * 1e6) = 1e11
//   * sqrtPriceX96 = sqrt(1e11) * 2^96 ≈ 25054144837504793118641380157
//
// Tick 范围说明:
// - Tick 与价格关系: price = 1.0001^tick
// - 对于 0.25% fee tier，tick spacing = 50（所有 tick 必须是 50 的倍数）
// - 当前目标价格 10^13 对应 tick ≈ 299,340
// - tickLower = 276,000 对应价格约 10^12 (1 USDT ≈ 1 CMT)
// - tickUpper = 322,650 对应价格约 10^14 (1 USDT ≈ 100 CMT)
// - 这个范围允许价格有较大的波动空间，同时保持合理的资金利用率

contract IntegratedTestStakingScript is Script {
    ERC20 public usdt;
    ChooseMeToken public chooseMeToken;
    NodeManager public nodeManager;
    StakingManager public stakingManager;
    DaoRewardManager public daoRewardManager;
    FomoTreasureManager public fomoTreasureManager;
    EventFundingManager public eventFundingManager;

    // PancakeSwap V3 相关合约地址 (BSC Mainnet)
    IV3NonfungiblePositionManager public constant positionManager =
        IV3NonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);
    IPancakeV3Factory public constant factory = IPancakeV3Factory(0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865);
    IPancakeV3SmartRouter public constant smartRouter =
        IPancakeV3SmartRouter(0x13f4EA83D0bd40E75C8222255bc855a974568Dd4);

    // V3 流动性池配置
    uint24 public constant poolFee = 2500; // 0.25% 费率
    // Tick spacing for 0.25% fee = 50
    // 目标价格: 1 USDT = 10 CMT, 考虑精度后 price_adjusted = 10^13
    // 当前价格对应 tick ≈ log(10^13) / log(1.0001) ≈ 299,340
    // 设置范围: 允许价格在 10^12 到 10^14 之间波动 (0.1x - 10x)
    // tickLower ≈ 276,000 (对应价格 ≈ 10^12, 即 1 USDT ≈ 1 CMT)
    // tickUpper ≈ 322,650 (对应价格 ≈ 10^14, 即 1 USDT ≈ 100 CMT)
    int24 public constant tickLower = -887200; // 必须是 50 的倍数
    int24 public constant tickUpper = 887200; // 必须是 50 的倍数
    uint256 public tokenId; // NFT position ID
    address public poolAddress;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        (
            address usdtAddress,
            address chooseMeTokenAddress,
            address stakingManagerAddress,
            address nodeManagerAddress,
            address daoRewardManagerAddress,
            address fomoTreasureManagerAddress,
            address eventFundingManagerAddress,,
        ) = getAddresses();

        console.log("deploy usdtTokenAddress:", usdtAddress);
        console.log("deploy proxyChooseMeToken:", chooseMeTokenAddress);
        console.log("deploy proxyStakingManager:", stakingManagerAddress);
        console.log("deploy proxyNodeManager:", nodeManagerAddress);
        console.log("deploy proxyDaoRewardManager:", daoRewardManagerAddress);
        console.log("deploy proxyFomoTreasureManager:", fomoTreasureManagerAddress);
        console.log("deploy proxyEventFundingManager:", eventFundingManagerAddress);

        usdt = ERC20(usdtAddress);
        chooseMeToken = ChooseMeToken(chooseMeTokenAddress);
        stakingManager = StakingManager(payable(stakingManagerAddress));
        nodeManager = NodeManager(payable(nodeManagerAddress));
        daoRewardManager = DaoRewardManager(payable(daoRewardManagerAddress));
        fomoTreasureManager = FomoTreasureManager(payable(fomoTreasureManagerAddress));
        eventFundingManager = EventFundingManager(payable(eventFundingManagerAddress));

        tokenId = nodeManager.positionTokenId();
        poolAddress = nodeManager.pool();

        // initCMT(deployerPrivateKey);
        // transfer(deployerPrivateKey);

        // testAddLiquidity(deployerPrivateKey);
        // readTokenIdAndPool();

        // testNodeAddLiquidity(deployerPrivateKey);
        // testSwap(deployerPrivateKey);
        // testSwapBurn(deployerPrivateKey);
    }

    /// forge script IntegratedTestStakingScript --sig "readTokenIdAndPool()" --rpc-url https://bsc-dataseed.binance.org
    /// @notice 读取指定地址拥有的所有 NFT Position Token ID 及其池子信息
    /// @dev 使用 ERC721Enumerable 接口枚举所有 position NFT
    function readTokenIdAndPool() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        IERC721 positionNFT = IERC721(address(positionManager));

        console.log("\n=== Reading NFT Position Token IDs ===");
        console.log("Address:", deployerAddress);

        // 获取该地址拥有的 NFT 数量
        uint256 balance = positionNFT.balanceOf(deployerAddress);
        console.log("Total NFT Positions:", balance);

        if (balance == 0) {
            console.log("No positions found for this address");
            return;
        }

        // 遍历所有 NFT 并读取详细信息
        for (uint256 i = 0; i < balance; i++) {
            // 使用 ERC721Enumerable 的 tokenOfOwnerByIndex 方法
            uint256 _tokenId = IERC721Enumerable(address(positionManager)).tokenOfOwnerByIndex(deployerAddress, i);

            console.log("\n--- Position #", i + 1, "---");
            console.log("Token ID:", _tokenId);

            // 读取 position 的详细信息
            (
                ,,
                address token0,
                address token1,
                uint24 fee,
                int24 tickLower,
                int24 tickUpper,
                uint128 liquidity,,,
                uint128 tokensOwed0,
                uint128 tokensOwed1
            ) = positionManager.positions(_tokenId);

            console.log("  Token0:", token0);
            console.log("  Token1:", token1);
            console.log("  Fee Tier:", fee);
            console.log("  Tick Lower:", uint256(uint24(tickLower)));
            console.log("  Tick Upper:", uint256(uint24(tickUpper)));
            console.log("  Liquidity:", liquidity);
            console.log("  Tokens Owed0:", tokensOwed0);
            console.log("  Tokens Owed1:", tokensOwed1);

            // 获取对应的池子地址
            address pool = factory.getPool(token0, token1, fee);
            console.log("  Pool Address:", pool);

            // 如果池子存在，读取池子的当前状态
            if (pool != address(0)) {
                IPancakeV3Pool poolContract = IPancakeV3Pool(pool);
                (uint160 sqrtPriceX96, int24 tick,,,,,) = poolContract.slot0();
                console.log("  Current Tick:", uint256(uint24(tick)));
                console.log("  Current SqrtPriceX96:", sqrtPriceX96);

                // 检查当前价格是否在 position 范围内
                if (tick >= tickLower && tick <= tickUpper) {
                    console.log("  Status: IN RANGE (earning fees)");
                } else {
                    console.log("  Status: OUT OF RANGE (not earning fees)");
                }
            }

            if (pool == nodeManager.pool()) {
                vm.startBroadcast(deployerPrivateKey);
                nodeManager.setPositionTokenId(_tokenId);
                stakingManager.setPositionTokenId(_tokenId);
                console.log("setPositionTokenId ===========>", _tokenId);
                vm.stopBroadcast();
            }
        }

        console.log("\n=== Summary ===");
        console.log("Total positions found:", balance);
    }

    function getAddresses()
        internal
        returns (
            address usdtAddress,
            address chooseMeTokenAddress,
            address stakingManagerAddress,
            address nodeManagerAddress,
            address daoRewardManagerAddress,
            address fomoTreasureManagerAddress,
            address eventFundingManagerAddress,
            uint256 tokenId,
            address poolAddress
        )
    {
        string memory json = vm.readFile("./cache/__deployed_addresses.json");
        usdtAddress = vm.parseJsonAddress(json, ".usdtTokenAddress");
        chooseMeTokenAddress = vm.parseJsonAddress(json, ".proxyChooseMeToken");
        stakingManagerAddress = vm.parseJsonAddress(json, ".proxyStakingManager");
        nodeManagerAddress = vm.parseJsonAddress(json, ".proxyNodeManager");
        daoRewardManagerAddress = vm.parseJsonAddress(json, ".proxyDaoRewardManager");
        fomoTreasureManagerAddress = vm.parseJsonAddress(json, ".proxyFomoTreasureManager");
        eventFundingManagerAddress = vm.parseJsonAddress(json, ".proxyEventFundingManager");
    }

    function testNodeAddLiquidity(uint256 deployerPrivateKey) internal {
        vm.startBroadcast(deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("\n=== NodeManager AddLiquidity Integration Test ===");
        console.log("Deployer Address:", deployerAddress);

        // 1. 检查 NodeManager 的配置
        address poolAddress = nodeManager.pool();
        uint256 currentPositionTokenId = nodeManager.positionTokenId();
        console.log("NodeManager Pool:", poolAddress);
        console.log("NodeManager Position Token ID:", currentPositionTokenId);

        // 2. 如果池子或 position 未设置，需要先创建
        if (poolAddress == address(0) || currentPositionTokenId == 0) {
            console.log("Setting up NodeManager pool and position...");
            setupNodeManagerLiquidity(deployerPrivateKey, deployerAddress);
            poolAddress = nodeManager.pool();
            currentPositionTokenId = nodeManager.positionTokenId();
        }

        // 3. 准备测试资金 - 向 NodeManager 转入 USDT
        uint256 testAmount = 50 * 1e18; // 2000 USDT
        uint256 nodeManagerUsdtBalance = usdt.balanceOf(address(nodeManager));
        console.log("NodeManager USDT Balance Before:", nodeManagerUsdtBalance);

        // 如果 NodeManager 余额不足，从 deployer 转入
        if (nodeManagerUsdtBalance < testAmount) {
            uint256 deployerBalance = usdt.balanceOf(deployerAddress);
            console.log("Deployer USDT Balance:", deployerBalance);
            require(deployerBalance >= testAmount, "Deployer: Insufficient USDT for test");

            console.log("Transferring USDT to NodeManager...");
            usdt.transfer(address(nodeManager), testAmount);
            nodeManagerUsdtBalance = usdt.balanceOf(address(nodeManager));
            console.log("NodeManager USDT Balance After Transfer:", nodeManagerUsdtBalance);
        }

        // 4. 调用 NodeManager.addLiquidity
        console.log("\n--- Calling NodeManager.addLiquidity ---");
        console.log("Adding liquidity amount:", testAmount);

        // 获取调用前的流动性信息
        (,, address token0Before, address token1Before,,,, uint128 liquidityBefore,,,,) =
            positionManager.positions(currentPositionTokenId);

        console.log("Position Before:");
        console.log("  Token0:", token0Before);
        console.log("  Token1:", token1Before);
        console.log("  Liquidity:", liquidityBefore);

        // 执行 addLiquidity
        nodeManager.addLiquidity(testAmount);

        // 5. 验证结果
        console.log("\n--- Verifying Results ---");

        // 获取调用后的流动性信息
        (,,,,,,, uint128 liquidityAfter,,, uint128 tokensOwed0After, uint128 tokensOwed1After) =
            positionManager.positions(currentPositionTokenId);

        console.log("Position After:");
        console.log("  Liquidity:", liquidityAfter);
        console.log("  Liquidity Increased:", liquidityAfter - liquidityBefore);
        console.log("  Tokens Owed0:", tokensOwed0After);
        console.log("  Tokens Owed1:", tokensOwed1After);

        // 检查 NodeManager 的余额变化
        uint256 nodeManagerUsdtBalanceAfter = usdt.balanceOf(address(nodeManager));
        uint256 nodeManagerCmtBalance = chooseMeToken.balanceOf(address(nodeManager));
        console.log("NodeManager USDT Balance After AddLiquidity:", nodeManagerUsdtBalanceAfter);
        console.log("NodeManager CMT Balance:", nodeManagerCmtBalance);

        // 验证流动性确实增加了
        require(liquidityAfter > liquidityBefore, "Liquidity should increase");
        console.log("\n[SUCCESS] Liquidity successfully added to position!");

        vm.stopBroadcast();
    }

    /// @notice 设置 NodeManager 的池子和初始流动性位置
    function setupNodeManagerLiquidity(uint256 deployerPrivateKey, address deployerAddress) internal {
        console.log("\n--- Setting up NodeManager Pool and Position ---");

        // 1. 确定 token0 和 token1 的顺序
        (address token0, address token1) = address(usdt) < address(chooseMeToken)
            ? (address(usdt), address(chooseMeToken))
            : (address(chooseMeToken), address(usdt));

        console.log("Token0:", token0);
        console.log("Token1:", token1);

        // 2. 检查或创建池子
        address poolAddress = factory.getPool(token0, token1, poolFee);

        if (poolAddress == address(0)) {
            console.log("Creating new pool...");
            // 初始价格设置为 1:10 (1 USDT = 10 CMT)
            // 注意: USDT=18位小数(1e18), CMT=6位小数(1e6)
            uint160 sqrtPriceX96;
            if (token0 == address(usdt)) {
                // token0=USDT(18位), token1=CMT(6位)
                // price = 10e6 / 1e18 = 1e-11
                // sqrtPriceX96 = sqrt(1e-11) * 2^96
                sqrtPriceX96 = 250541448375048; // sqrt(1e-11) * 2^96
            } else {
                // token0=CMT(6位), token1=USDT(18位)
                // price = 0.1e18 / 1e6 = 1e11
                // sqrtPriceX96 = sqrt(1e11) * 2^96
                sqrtPriceX96 = 25054144837504793118641380157; // sqrt(1e11) * 2^96
            }
            poolAddress = positionManager.createAndInitializePoolIfNecessary(token0, token1, poolFee, sqrtPriceX96);
            console.log("Pool created:", poolAddress);
        } else {
            console.log("Pool already exists:", poolAddress);
        }

        // 3. 设置 NodeManager 的池子地址
        nodeManager.setPool(poolAddress);
        console.log("Pool set in NodeManager");

        // 4. 创建初始流动性位置
        console.log("Creating initial liquidity position...");

        uint256 initialUsdtAmount = 1000 * 1e18; // 1000 USDT
        uint256 initialCmtAmount = 10000 * 1e6; // 10000 CMT

        (uint256 amount0Desired, uint256 amount1Desired) = address(usdt) < address(chooseMeToken)
            ? (initialUsdtAmount, initialCmtAmount)
            : (initialCmtAmount, initialUsdtAmount);

        // 授权
        usdt.approve(address(positionManager), initialUsdtAmount);
        chooseMeToken.approve(address(positionManager), initialCmtAmount);

        // 铸造 NFT 位置
        IV3NonfungiblePositionManager.MintParams memory params = IV3NonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: poolFee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: deployerAddress, // NFT 归属于 deployer，然后可以转给 NodeManager
            deadline: block.timestamp + 300
        });

        (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = positionManager.mint(params);

        console.log("Position created:");
        console.log("  Token ID:", newTokenId);
        console.log("  Liquidity:", liquidity);
        console.log("  Amount0:", amount0);
        console.log("  Amount1:", amount1);

        // 5. 设置 NodeManager 的 positionTokenId
        nodeManager.setPositionTokenId(newTokenId);
        console.log("Position Token ID set in NodeManager:", newTokenId);

        // 注意: 在生产环境中，需要将 NFT 的所有权转移给 NodeManager
        // 这需要 Position Manager 实现 ERC721 的 transferFrom 方法
        // positionManager.transferFrom(deployerAddress, address(nodeManager), newTokenId);
    }

    function testAddLiquidity(uint256 deployerPrivateKey) internal {
        vm.startBroadcast(deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("=== PancakeSwap V3 Add Liquidity Test ===");
        console.log("Deployer Address:", deployerAddress);

        // 0. 验证 tick 配置
        logTickInfo();

        // 1. 检查代币余额
        uint256 usdtBalance = usdt.balanceOf(deployerAddress);
        uint256 cmtBalance = chooseMeToken.balanceOf(deployerAddress);
        console.log("\n=== Token Balances ===");
        console.log("USDT Balance:", usdtBalance);
        console.log("CMT Balance:", cmtBalance);

        require(usdtBalance > 0, "Insufficient USDT balance");
        require(cmtBalance > 0, "Insufficient CMT balance");

        // 2. 准备流动性数量
        uint256 usdtAmount = 1000 * 1e18; // 1000 USDT
        uint256 cmtAmount = 10000 * 1e6; // 10000 CMT (假设CMT是6位小数)

        require(usdtBalance >= usdtAmount, "Not enough USDT");
        require(cmtBalance >= cmtAmount, "Not enough CMT");

        // 3. 确定token0和token1的顺序（必须按地址排序）
        (address token0, address token1) = address(usdt) < address(chooseMeToken)
            ? (address(usdt), address(chooseMeToken))
            : (address(chooseMeToken), address(usdt));

        (uint256 amount0Desired, uint256 amount1Desired) =
            address(usdt) < address(chooseMeToken) ? (usdtAmount, cmtAmount) : (cmtAmount, usdtAmount);

        console.log("Token0:", token0);
        console.log("Token1:", token1);
        console.log("Amount0:", amount0Desired);
        console.log("Amount1:", amount1Desired);

        // 4. 授权 Position Manager
        console.log("Approving Position Manager...");
        usdt.approve(address(positionManager), usdtAmount);
        chooseMeToken.approve(address(positionManager), cmtAmount);

        // 5. 检查池子是否存在，不存在则创建并初始化
        address poolAddress = factory.getPool(token0, token1, poolFee);
        console.log("Pool Address:", poolAddress);

        console.log("=========", Math.sqrt((10 ** 7) * (2 ** 192)) / 1e9);
        console.log("=========", Math.sqrt(((10 ** 18) * (2 ** 192)) / (10 ** 7)));

        if (poolAddress == address(0)) {
            console.log("Pool does not exist, creating and initializing...");
            // 初始价格设置为 1:10 (1 USDT = 10 CMT)
            // 注意: USDT=18位小数(1e18), CMT=6位小数(1e6)
            // sqrtPriceX96 = sqrt(price) * 2^96
            // price = amount1 / amount0 (原始代币数量，包含精度)
            // price = sqrt(amount1 * 2^(96*2)) / sqrt(amount0)
            uint160 sqrtPriceX96;
            if (token0 == address(usdt)) {
                // token0=USDT(18位), token1=CMT(6位)
                // 目标: 1 USDT (1e18单位) = 10 CMT (10e6单位)
                // price = sqrt((2^192 * 10^7) / 1e18)
                sqrtPriceX96 = 250541448375047931186413;
            } else {
                // token0=CMT(6位), token1=USDT(18位)
                // 目标: 1 CMT (1e6单位) = 0.1 USDT (0.1e18单位)
                // price = sqrt((2^192 * 10^18) / 1e7)
                sqrtPriceX96 = 25056344881171517265510420726122707;
            }

            poolAddress = positionManager.createAndInitializePoolIfNecessary(token0, token1, poolFee, sqrtPriceX96);
            console.log("Pool created:", poolAddress);
        }

        // 6. 添加流动性
        console.log("Minting liquidity position...");
        IV3NonfungiblePositionManager.MintParams memory params = IV3NonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: poolFee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0, // 在测试中设置为0，生产环境需要设置合理的滑点保护
            amount1Min: 0,
            recipient: deployerAddress,
            deadline: block.timestamp + 300 // 5分钟超时
        });

        (uint256 _tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = positionManager.mint(params);

        console.log("Position NFT Token ID: ===============>", _tokenId);
        console.log("Liquidity Added:", liquidity);
        console.log("amount0Desired: ", amount0Desired);
        console.log("amount1Desired: ", amount1Desired);
        console.log("Amount0 Used: ", amount0);
        console.log("Amount1 Used: ", amount1);

        // 计算实际使用率
        uint256 usage0Percent = (amount0 * 100) / amount0Desired;
        uint256 usage1Percent = (amount1 * 100) / amount1Desired;
        console.log("Amount0 Usage Rate:", usage0Percent, "%");
        console.log("Amount1 Usage Rate:", usage1Percent, "%");

        // 验证使用率是否合理（至少 80%）
        if (usage0Percent < 80 || usage1Percent < 80) {
            console.log("WARNING: Token usage rate is less than 80%. Consider adjusting tick range or initial price.");
        }

        tokenId = _tokenId;

        // 7. 验证流动性位置
        testVerifyPosition(_tokenId);

        // 7.1 验证池子价格
        testVerifyPrice(poolAddress);

        // 8. 测试增加流动性
        // testIncreaseLiquidity(_tokenId, deployerAddress);

        // 9. 测试收集手续费
        // testCollectFees(_tokenId, deployerAddress);

        // tokenId 和 poolAddress 存储到合约状态，供 NodeManager 使用
        // 但是这里获取的 tokenId 可能存在问题
        nodeManager.setPool(poolAddress);
        // nodeManager.setPositionTokenId(_tokenId);

        stakingManager.setPool(poolAddress);
        // stakingManager.setPositionTokenId(_tokenId);

        vm.stopBroadcast();
    }

    /// @notice 验证流动性位置信息
    function testVerifyPosition(uint256 _tokenId) internal view {
        console.log("\n=== Verify Position ===");
        (
            ,,
            address token0,
            address token1,
            uint24 fee,
            int24 _tickLower,
            int24 _tickUpper,
            uint128 liquidity,,,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = positionManager.positions(_tokenId);

        console.log("Position Details:");
        console.log("  Token0:", token0);
        console.log("  Token1:", token1);
        console.log("  Fee:", fee);
        console.log("  Tick Lower:", uint256(uint24(_tickLower)));
        console.log("  Tick Upper:", uint256(uint24(_tickUpper)));
        console.log("  Liquidity:", liquidity);
        console.log("  Tokens Owed0:", tokensOwed0);
        console.log("  Tokens Owed1:", tokensOwed1);
    }

    /// @notice 验证池子当前价格
    /// @dev 检查价格是否符合预期，并计算实际兑换率
    function testVerifyPrice(address poolAddress) internal view {
        console.log("\n=== Verify Pool Price ===");

        IPancakeV3Pool pool = IPancakeV3Pool(poolAddress);

        // 获取池子信息
        address token0 = pool.token0();
        address token1 = pool.token1();
        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();

        console.log("Pool Address:", poolAddress);
        console.log("Token0:", token0);
        console.log("Token1:", token1);
        console.log("Current Tick:", uint256(uint24(tick)));
        console.log("SqrtPriceX96:", sqrtPriceX96);

        // 计算实际价格
        // price = (sqrtPriceX96 / 2^96)^2
        // 为了避免精度丢失，我们分步计算
        uint256 price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 192; // 除以 2^192

        console.log("\nPrice Analysis:");
        console.log("  Raw Price (amount1/amount0):", price);

        // 根据 token 顺序解释价格
        if (token0 == address(usdt)) {
            // token0 = USDT(18位), token1 = CMT(6位)
            // price = CMT数量 / USDT数量 (原始单位)
            // 实际兑换率: 1 USDT = ? CMT
            // 需要调整精度: price * 10^18 / 10^6 = price * 10^12

            console.log("  Token Pair: USDT/CMT");

            // 计算 1 USDT(1e18) 能换多少 CMT(1e6)
            // 由于 price 是基于最小单位，我们需要调整
            // 1 USDT(1e18) / price = CMT数量(1e6单位)
            // 实际CMT数量 = (1e18 / price) * price = 非常小的数
            // 正确计算: price 表示 1个token0最小单位 能换多少 token1最小单位
            // 所以 1 USDT (1e18单位) 能换 price * 1e18 个 token1最小单位
            // = price * 1e18 / 1e6 个 CMT

            if (price > 0) {
                // price = 1e-11 意味着 1个USDT最小单位(1) 换 1e-11 个CMT最小单位
                // 1 USDT (1e18) 换 1e-11 * 1e18 = 1e7 个CMT最小单位 = 10 CMT(1e6单位)
                console.log("  Expected: 1 USDT = 10 CMT");
                console.log("  Actual price suggests: Check calculation below");

                // 由于 price 可能非常小，使用 sqrtPriceX96 来反推
                // sqrtPrice = sqrt(price) * 2^96
                // 目标: 1 USDT = 10 CMT
                // 即: (10 * 1e6) / (1 * 1e18) = 1e-11
                // sqrtPriceX96 应该约等于 250541448375048

                uint256 expectedSqrtPrice = 250541448375048;
                uint256 priceDiff = sqrtPriceX96 > expectedSqrtPrice
                    ? sqrtPriceX96 - expectedSqrtPrice
                    : expectedSqrtPrice - sqrtPriceX96;
                uint256 priceDeviationPercent = (priceDiff * 100) / expectedSqrtPrice;

                console.log("  Expected SqrtPriceX96:", expectedSqrtPrice);
                console.log("  Price Deviation:", priceDeviationPercent, "%");

                if (priceDeviationPercent > 5) {
                    console.log("  WARNING: Price deviation > 5%");
                } else {
                    console.log("  PASS: Price is within acceptable range");
                }
            }
        } else {
            // token0 = CMT(6位), token1 = USDT(18位)
            console.log("  Token Pair: CMT/USDT");

            if (price > 0) {
                console.log("  Expected: 1 CMT = 0.1 USDT");

                // 目标: 1 CMT = 0.1 USDT
                // 即: (0.1 * 1e18) / (1 * 1e6) = 1e11
                // sqrtPriceX96 应该约等于 25054144837504793118641380157

                uint256 expectedSqrtPrice = 25054144837504793118641380157;
                uint256 priceDiff = sqrtPriceX96 > expectedSqrtPrice
                    ? sqrtPriceX96 - expectedSqrtPrice
                    : expectedSqrtPrice - sqrtPriceX96;
                uint256 priceDeviationPercent = (priceDiff * 100) / expectedSqrtPrice;

                console.log("  Expected SqrtPriceX96:", expectedSqrtPrice);
                console.log("  Price Deviation:", priceDeviationPercent, "%");

                if (priceDeviationPercent > 5) {
                    console.log("  WARNING: Price deviation > 5%");
                } else {
                    console.log("  PASS: Price is within acceptable range");
                }
            }
        }

        // Tick 价格范围检查
        console.log("\nTick Range Check:");
        console.log("  Current Tick:", uint256(uint24(tick)));
        console.log("  Position Tick Lower:", uint256(uint24(tickLower)));
        console.log("  Position Tick Upper:", uint256(uint24(tickUpper)));

        if (tick >= tickLower && tick <= tickUpper) {
            console.log("  PASS: Current price is within position range");
        } else {
            console.log("  WARNING: Current price is outside position range!");
        }
    }

    /// @notice 测试普通交易（Swap）
    /// @dev 使用 PancakeSwap V3 SmartRouter 测试 USDT <-> CMT 的交易功能
    function testSwap(uint256 deployerPrivateKey) internal {
        vm.startBroadcast(deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("\n=== Test Swap via SmartRouter (Trading) ===");
        console.log("Deployer Address:", deployerAddress);
        console.log("SmartRouter Address:", address(smartRouter));

        IPancakeV3Pool pool = IPancakeV3Pool(poolAddress);

        // 获取池子信息
        address token0 = pool.token0();
        address token1 = pool.token1();
        (uint160 sqrtPriceX96Before,,,,,,) = pool.slot0();

        console.log("\nPool Info:");
        console.log("  Pool Address:", poolAddress);
        console.log("  Token0:", token0);
        console.log("  Token1:", token1);
        console.log("  SqrtPriceX96 Before:", sqrtPriceX96Before);

        // 测试 1: USDT -> CMT 交易
        console.log("\n--- Test Swap: USDT -> CMT ---");
        uint256 swapUsdtAmount = 100 * 1e18; // 100 USDT

        uint256 usdtBalanceBefore = usdt.balanceOf(deployerAddress);
        uint256 cmtBalanceBefore = chooseMeToken.balanceOf(deployerAddress);

        console.log("Before Swap:");
        console.log("  USDT Balance:", usdtBalanceBefore);
        console.log("  CMT Balance:", cmtBalanceBefore);
        console.log("  Swap Amount: 100 USDT");

        require(usdtBalanceBefore >= swapUsdtAmount, "Insufficient USDT balance for swap");

        // 授权 SmartRouter 使用 USDT
        usdt.approve(address(smartRouter), swapUsdtAmount);
        console.log("  USDT approved to SmartRouter");

        // 构造 exactInputSingle 参数
        // 设置最小输出为期望输出的 95%（5% 滑点保护）
        uint256 expectedCmtOut = (swapUsdtAmount * 10 * 1e6) / 1e18; // 预期按 1:10 比例
        uint256 minCmtOut = (expectedCmtOut * 80) / 100; // 5% 滑点

        IPancakeV3SmartRouter.ExactInputSingleParams memory params = IPancakeV3SmartRouter.ExactInputSingleParams({
            tokenIn: address(usdt),
            tokenOut: address(chooseMeToken),
            fee: poolFee,
            recipient: deployerAddress,
            deadline: block.timestamp + 300,
            amountIn: swapUsdtAmount,
            amountOutMinimum: minCmtOut,
            sqrtPriceLimitX96: 0 // 0 表示不设置价格限制
        });

        console.log("  Expected CMT Out (approx):", expectedCmtOut);
        console.log("  Min CMT Out (with 5% slippage):", minCmtOut);

        // 执行交易
        uint256 amountOut = smartRouter.exactInputSingle(params);

        uint256 usdtBalanceAfter1 = usdt.balanceOf(deployerAddress);
        uint256 cmtBalanceAfter1 = chooseMeToken.balanceOf(deployerAddress);
        (uint160 sqrtPriceX96After1,,,,,,) = pool.slot0();

        console.log("\nAfter Swap:");
        console.log("  USDT Balance:", usdtBalanceAfter1);
        console.log("  CMT Balance:", cmtBalanceAfter1);
        console.log("  USDT Used:", usdtBalanceBefore - usdtBalanceAfter1);
        console.log("  CMT Received:", amountOut);
        console.log("  SqrtPriceX96 After:", sqrtPriceX96After1);

        // 计算实际兑换率
        uint256 usdtUsed = usdtBalanceBefore - usdtBalanceAfter1;
        if (usdtUsed > 0 && amountOut > 0) {
            // 计算每 1 USDT 能换多少 CMT
            // CMT 是 6 位小数，USDT 是 18 位小数
            // rate = (amountOut / 1e6) / (usdtUsed / 1e18) = (amountOut * 1e18) / (usdtUsed * 1e6)
            uint256 rate = (amountOut * 1e12) / usdtUsed; // 归一化
            console.log("  Exchange Rate: 1 USDT =", rate, "CMT");
        }

        // 测试 2: CMT -> USDT 交易（反向交易）
        console.log("\n--- Test Swap: CMT -> USDT ---");
        uint256 swapCmtAmount = 500 * 1e6; // 500 CMT

        console.log("Before Swap:");
        console.log("  USDT Balance:", usdtBalanceAfter1);
        console.log("  CMT Balance:", cmtBalanceAfter1);
        console.log("  Swap Amount: 500 CMT");

        require(cmtBalanceAfter1 >= swapCmtAmount, "Insufficient CMT balance for swap");

        // 授权 SmartRouter 使用 CMT
        chooseMeToken.approve(address(smartRouter), swapCmtAmount);
        console.log("  CMT approved to SmartRouter");

        // 构造 exactInputSingle 参数
        // 预期按 1:0.1 比例（1 CMT = 0.1 USDT）
        uint256 expectedUsdtOut = (swapCmtAmount * 1e18) / (10 * 1e6); // 500 CMT = 50 USDT
        uint256 minUsdtOut = (expectedUsdtOut * 95) / 100; // 5% 滑点

        IPancakeV3SmartRouter.ExactInputSingleParams memory params2 = IPancakeV3SmartRouter.ExactInputSingleParams({
            tokenIn: address(chooseMeToken),
            tokenOut: address(usdt),
            fee: poolFee,
            recipient: deployerAddress,
            deadline: block.timestamp + 300,
            amountIn: swapCmtAmount,
            amountOutMinimum: minUsdtOut,
            sqrtPriceLimitX96: 0
        });

        console.log("  Expected USDT Out (approx):", expectedUsdtOut);
        console.log("  Min USDT Out (with 5% slippage):", minUsdtOut);

        // 执行反向交易
        uint256 amountOut2 = smartRouter.exactInputSingle(params2);

        uint256 usdtBalanceAfter2 = usdt.balanceOf(deployerAddress);
        uint256 cmtBalanceAfter2 = chooseMeToken.balanceOf(deployerAddress);
        (uint160 sqrtPriceX96After2,,,,,,) = pool.slot0();

        console.log("\nAfter Swap:");
        console.log("  USDT Balance:", usdtBalanceAfter2);
        console.log("  CMT Balance:", cmtBalanceAfter2);
        console.log("  CMT Used:", cmtBalanceAfter1 - cmtBalanceAfter2);
        console.log("  USDT Received:", amountOut2);
        console.log("  SqrtPriceX96 After:", sqrtPriceX96After2);

        // // 计算反向兑换率
        // uint256 cmtUsed = cmtBalanceAfter1 - cmtBalanceAfter2;
        // if (cmtUsed > 0 && amountOut2 > 0) {
        //     // 计算每 1 CMT 能换多少 USDT
        //     // rate = (amountOut2 / 1e18) / (cmtUsed / 1e6) = (amountOut2 * 1e6) / (cmtUsed * 1e18)
        //     uint256 rate2 = (amountOut2 * 1e6) / (cmtUsed * 1e18); // 结果是 1e6 精度
        //     console.log("  Exchange Rate: 1 CMT =", rate2, "* 1e-6 USDT (i.e.", rate2, "/ 1e6 USDT)");
        //     console.log("  Exchange Rate: 10 CMT =", (rate2 * 10) / 1e6, "USDT (approx)");
        // }

        // console.log("\n[SUCCESS] Swap tests via SmartRouter completed!");
        vm.stopBroadcast();
    }

    /// @notice 测试增加流动性
    function testIncreaseLiquidity(uint256 _tokenId, address deployerAddress) internal {
        console.log("\n=== Test Increase Liquidity ===");

        // 准备额外的代币
        uint256 additionalUsdt = 500 * 1e18; // 500 USDT
        uint256 additionalCmt = 5000 * 1e6; // 5000 CMT

        uint256 usdtBalance = usdt.balanceOf(deployerAddress);
        uint256 cmtBalance = chooseMeToken.balanceOf(deployerAddress);

        if (usdtBalance < additionalUsdt || cmtBalance < additionalCmt) {
            console.log("Insufficient balance for increasing liquidity, skipping...");
            return;
        }

        // 确定token0和token1的顺序
        (uint256 amount0Desired, uint256 amount1Desired) =
            address(usdt) < address(chooseMeToken) ? (additionalUsdt, additionalCmt) : (additionalCmt, additionalUsdt);

        // 授权额外的代币
        usdt.approve(address(positionManager), additionalUsdt);
        chooseMeToken.approve(address(positionManager), additionalCmt);

        IV3NonfungiblePositionManager.IncreaseLiquidityParams memory params =
            IV3NonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: _tokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 300
            });

        (uint128 liquidity, uint256 amount0, uint256 amount1) = positionManager.increaseLiquidity(params);

        console.log("Liquidity Increased:", liquidity);
        console.log("Amount0 Added:", amount0);
        console.log("Amount1 Added:", amount1);
    }

    /// @notice 测试收集手续费
    function testCollectFees(uint256 _tokenId, address deployerAddress) internal {
        console.log("\n=== Test Collect Fees ===");

        IV3NonfungiblePositionManager.CollectParams memory params = IV3NonfungiblePositionManager.CollectParams({
            tokenId: _tokenId, recipient: deployerAddress, amount0Max: type(uint128).max, amount1Max: type(uint128).max
        });

        (uint256 amount0, uint256 amount1) = positionManager.collect(params);

        console.log("Fees Collected:");
        console.log("  Amount0:", amount0);
        console.log("  Amount1:", amount1);
    }

    /// @notice 验证 tick 设置的辅助函数
    /// @dev 在添加流动性前调用，确保 tick 设置合理
    function logTickInfo() internal view {
        console.log("\n=== Tick Configuration Info ===");
        console.log("Pool Fee:", poolFee, "(0.25%)");
        console.log("Tick Spacing: 50 (for 0.25% fee tier)");
        console.log("Tick Lower:", uint256(uint24(tickLower)));
        console.log("Tick Upper:", uint256(uint24(tickUpper)));
        console.log("Tick Range:", uint256(uint24(tickUpper - tickLower)));

        // 验证 tick 是否是 tick spacing 的倍数
        require(tickLower % 50 == 0, "tickLower must be multiple of 50");
        require(tickUpper % 50 == 0, "tickUpper must be multiple of 50");
        console.log("Tick validation: PASSED");

        console.log("\nPrice Range:");
        console.log("  At tickLower (276,000): ~10^12 (1 USDT ~ 1 CMT)");
        console.log("  Target price: ~10^13 (1 USDT = 10 CMT)");
        console.log("  At tickUpper (322,650): ~10^14 (1 USDT ~ 100 CMT)");
    }

    function initCMT(uint256 deployerPrivateKey) internal {
        vm.startBroadcast(deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);

        chooseMeToken.setPoolAddress(
            ChooseMeTokenStorage.ChooseMePool({
                nodePool: address(nodeManager),
                daoRewardPool: address(daoRewardManager),
                airdropPool: deployerAddress,
                normalPool: deployerAddress,
                techRewardsPool: deployerAddress,
                ecosystemPool: deployerAddress,
                foundingStrategyPool: deployerAddress,
                marketingDevelopmentPool: deployerAddress,
                subTokenPool: deployerAddress
            })
        );

        chooseMeToken.poolAllocate();
        vm.stopBroadcast();
    }

    function transfer(uint256 deployerPrivateKey) internal {
        vm.startBroadcast(deployerPrivateKey);
        usdt.transfer(0xD837FF8cb366D1f9ebDB0659b066b709804D52bc, 100000 * 1e18);
        chooseMeToken.transfer(0xD837FF8cb366D1f9ebDB0659b066b709804D52bc, 100000 * 1e6);

        chooseMeToken.transfer(0x7f345497612FbA3DFb923b422D67108BB5894EA6, 100000 * 1e6);
        chooseMeToken.transfer(0x7f345497612FbA3DFb923b422D67108BB5894EA6, 100000 * 1e6);

        chooseMeToken.transfer(0xcCA370146cabEb663a277c80db355aAf749fa3eb, 100000 * 1e6);
        chooseMeToken.transfer(0xcCA370146cabEb663a277c80db355aAf749fa3eb, 100000 * 1e6);
        vm.stopBroadcast();
    }

    /// @notice 测试 StakingManager.swapBurn 功能
    /// @dev 集成测试 swapBurn 方法：用 USDT 交换 CMT 然后销毁
    function testSwapBurn(uint256 deployerPrivateKey) internal {
        vm.startBroadcast(deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("\n=== StakingManager SwapBurn Integration Test ===");
        console.log("Deployer Address:", deployerAddress);

        // 1. 检查 StakingManager 的配置
        address poolAddress = stakingManager.pool();
        address stakingOperatorManager = stakingManager.stakingOperatorManager();
        console.log("StakingManager Pool:", poolAddress);
        console.log("StakingOperatorManager:", stakingOperatorManager);

        require(poolAddress != address(0), "Pool not set in StakingManager");

        // 2. 准备测试资金 - 向 StakingManager 转入 USDT
        uint256 testSwapAmount = 100 * 1e18; // 100 USDT
        uint256 stakingManagerUsdtBalance = usdt.balanceOf(address(stakingManager));
        console.log("\nBefore Test:");
        console.log("  StakingManager USDT Balance:", stakingManagerUsdtBalance);

        // 如果 StakingManager 余额不足，从 deployer 转入
        if (stakingManagerUsdtBalance < testSwapAmount) {
            uint256 deployerBalance = usdt.balanceOf(deployerAddress);
            console.log("  Deployer USDT Balance:", deployerBalance);
            require(deployerBalance >= testSwapAmount, "Deployer: Insufficient USDT for test");

            console.log("  Transferring USDT to StakingManager...");
            usdt.transfer(address(stakingManager), testSwapAmount);
            stakingManagerUsdtBalance = usdt.balanceOf(address(stakingManager));
            console.log("  StakingManager USDT Balance After Transfer:", stakingManagerUsdtBalance);
        }

        // 3. 获取初始余额和总供应量
        uint256 cmtTotalSupplyBefore = chooseMeToken.totalSupply();
        uint256 stakingManagerCmtBalanceBefore = chooseMeToken.balanceOf(address(stakingManager));

        console.log("\nBefore swapBurn:");
        console.log("  CMT Total Supply:", cmtTotalSupplyBefore);
        console.log("  StakingManager CMT Balance:", stakingManagerCmtBalanceBefore);
        console.log("  Swap Amount: ", testSwapAmount, "USDT");

        // 4. 执行 swapBurn
        // 注意：swapBurn 只能由 stakingOperatorManager 调用
        // 如果当前部署者不是 stakingOperatorManager，测试将失败
        // 需要确保部署时正确设置了 stakingOperatorManager 或使用正确的账户执行此测试
        console.log("\n--- Calling StakingManager.swapBurn ---");

        if (deployerAddress != stakingOperatorManager) {
            console.log("  WARNING: Deployer is not stakingOperatorManager");
            console.log("  This call will revert. Please ensure you run this test with the correct account.");
            console.log("  Current deployer:", deployerAddress);
            console.log("  Required stakingOperatorManager:", stakingOperatorManager);
        }

        console.log("  Amount:", testSwapAmount);

        // 记录调用前的池子状态
        IPancakeV3Pool pool = IPancakeV3Pool(poolAddress);
        (uint160 sqrtPriceX96Before,,,,,,) = pool.slot0();
        console.log("  Pool SqrtPriceX96 Before:", sqrtPriceX96Before);

        // 执行 swapBurn
        stakingManager.swapBurn(testSwapAmount);

        // 5. 验证结果
        console.log("\n--- Verifying Results ---");

        // 获取调用后的余额和总供应量
        uint256 cmtTotalSupplyAfter = chooseMeToken.totalSupply();
        uint256 stakingManagerCmtBalanceAfter = chooseMeToken.balanceOf(address(stakingManager));
        uint256 stakingManagerUsdtBalanceAfter = usdt.balanceOf(address(stakingManager));

        console.log("After swapBurn:");
        console.log("  CMT Total Supply:", cmtTotalSupplyAfter);
        console.log("  CMT Burned:", cmtTotalSupplyBefore - cmtTotalSupplyAfter);
        console.log("  StakingManager CMT Balance:", stakingManagerCmtBalanceAfter);
        console.log("  StakingManager USDT Balance:", stakingManagerUsdtBalanceAfter);
        console.log("  USDT Used:", stakingManagerUsdtBalance - stakingManagerUsdtBalanceAfter);

        // 记录调用后的池子状态
        (uint160 sqrtPriceX96After,,,,,,) = pool.slot0();
        console.log("  Pool SqrtPriceX96 After:", sqrtPriceX96After);

        // 验证 CMT 总供应量减少
        require(cmtTotalSupplyAfter < cmtTotalSupplyBefore, "CMT should be burned");

        // 验证 USDT 被使用
        require(stakingManagerUsdtBalanceAfter < stakingManagerUsdtBalance, "USDT should be used for swap");

        uint256 cmtBurned = cmtTotalSupplyBefore - cmtTotalSupplyAfter;
        uint256 usdtUsed = stakingManagerUsdtBalance - stakingManagerUsdtBalanceAfter;

        console.log("\n[SUCCESS] SwapBurn test completed!");
        console.log("  Summary:");
        console.log("    USDT Swapped:", usdtUsed);
        console.log("    CMT Burned:", cmtBurned);
        console.log("    Effective Rate: 1 USDT =", (cmtBurned * 1e18) / (usdtUsed * 1e6), "* 1e-18 CMT");

        vm.stopBroadcast();
    }
}
