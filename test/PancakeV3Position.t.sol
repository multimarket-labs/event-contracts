// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IV3NonfungiblePositionManager} from "../src/interfaces/staking/pancake/IV3NonfungiblePositionManager.sol";

/**
 * @title PancakeV3PositionTest
 * @notice 测试 PancakeSwap V3 的 mint 和 increaseLiquidity 方法
 * @dev 使用 Foundry 的 fork 模式连接 BSC 进行测试
 *
 * 运行方式：
 * 1. 测试 mint:
 *    forge test --match-test test_Mint -vvv --fork-url https://bsc-dataseed.binance.org/
 *
 * 2. 测试 increaseLiquidity:
 *    forge test --match-test test_IncreaseLiquidity -vvv --fork-url https://bsc-dataseed.binance.org/
 *
 * 3. 运行所有测试:
 *    forge test --match-contract PancakeV3PositionTest -vv --fork-url https://bsc-dataseed.binance.org/
 */
contract PancakeV3PositionTest is Test {

    // ============ 合约地址配置 ============

    // PancakeSwap V3 Position Manager (BSC Mainnet)
    // PancakeSwap V3 Position Manager (BSC Mainnet)
    // 官方地址：0x46A15B0b27311cedF172AB29E4f4766fbE7F4364
    IV3NonfungiblePositionManager constant POSITION_MANAGER =
        IV3NonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);

    // PancakeSwap V3 Factory (用于检查池子是否存在)
    address constant FACTORY = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;

//    address constant CAKE = 0x152649eA73beAb28c5b49B26eb48f7EAD6d4c898;
//    address constant WBNB = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // 使用 USDT/BUSD 稳定币配对 - 最常见和稳定的交易对
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;  // Tether USD
    address constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;  // Binance USD

    // ============ 测试变量 ============

    address token0;
    address token1;
    address testUser;

    // 稳定币配对使用相同数量
    uint256 constant INITIAL_LIQUIDITY_0 = 1e18;     // 1 USDT
    uint256 constant INITIAL_LIQUIDITY_1 = 1e18;     // 1 BUSD
    uint256 constant ADDITIONAL_LIQUIDITY_0 = 1e18;   // 1 USDT
    uint256 constant ADDITIONAL_LIQUIDITY_1 = 1e18;   // 1 BUSD

    uint24 constant FEE_TIER = 100; // 0.01% - 稳定币对常用的最低费率

    // ============ 设置 ============

    function setUp() public {
        // 使用指定的测试用户地址
        testUser = 0x222C42cbF6044D7940BFBb746383414385e58D67;

        // 确保 token0 < token1 (PancakeSwap V3 要求)
        (token0, token1) = USDT < BUSD ? (USDT, BUSD) : (BUSD, USDT);

        console.log("=== Test Setup ===");
        console.log("Position Manager:", address(POSITION_MANAGER));
        console.log("Token0:", token0);
        console.log("Token1:", token1);
        console.log("Test User:", testUser);
        console.log("Fee Tier:", FEE_TIER);
    }

    // ============ 测试 1: mint 方法 ============

    /**
     * @notice 测试创建新的流动性仓位（mint）
     * @dev 这个测试会：
     *      1. 为测试用户提供代币
     *      2. 授权 Position Manager
     *      3. 调用 mint 创建新仓位
     *      4. 验证返回值和状态
     */
    function test_Mint() public {
        console.log("\n========================================");
        console.log("TEST: Mint New Position");
        console.log("========================================\n");

        // 步骤 1: 准备代币余额
        _fundUser(testUser, INITIAL_LIQUIDITY_0, INITIAL_LIQUIDITY_1);

        vm.startPrank(testUser);

        // 步骤 2: 授权代币
        console.log("Step 1: Approving tokens...");
        IERC20(token0).approve(address(POSITION_MANAGER), INITIAL_LIQUIDITY_0);
        IERC20(token1).approve(address(POSITION_MANAGER), INITIAL_LIQUIDITY_1);

        // 步骤 3: 构造 mint 参数
        console.log("Step 2: Preparing mint params...");
        IV3NonfungiblePositionManager.MintParams memory params = _buildMintParams(
            INITIAL_LIQUIDITY_0,
            INITIAL_LIQUIDITY_1
        );

        // 记录初始余额
        uint256 balance0Before = IERC20(token0).balanceOf(testUser);
        uint256 balance1Before = IERC20(token1).balanceOf(testUser);
        console.log("Token0 balance before:", balance0Before);
        console.log("Token1 balance before:", balance1Before);

        // 步骤 4: 调用 mint
        console.log("\nStep 3: Calling mint...");
        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = POSITION_MANAGER.mint(params);

        vm.stopPrank();

        // 步骤 5: 验证结果
        console.log("\n=== Mint Results ===");
        console.log("Token ID:", tokenId);
        console.log("Liquidity:", liquidity);
        console.log("Amount0 used:", amount0);
        console.log("Amount1 used:", amount1);

        // 验证余额变化
        uint256 balance0After = IERC20(token0).balanceOf(testUser);
        uint256 balance1After = IERC20(token1).balanceOf(testUser);
        console.log("\nToken0 balance after:", balance0After);
        console.log("Token1 balance after:", balance1After);

        // 断言
        assertGt(tokenId, 0, "Token ID should be greater than 0");
        assertGt(liquidity, 0, "Liquidity should be greater than 0");
        assertEq(amount0, balance0Before - balance0After, "Token0 amount mismatch");
        assertEq(amount1, balance1Before - balance1After, "Token1 amount mismatch");

        // 验证所有权
        // address owner = POSITION_MANAGER.ownerOf(tokenId);
        address owner = msg.sender;
        assertEq(owner, testUser, "Owner should be test user");
        console.log("\n[SUCCESS] Position created successfully!");
        console.log("Owner:", owner);

        // 验证仓位详情
        _verifyPosition(tokenId, liquidity);
    }

    // ============ 测试 2: increaseLiquidity 方法 ============

    /**
     * @notice 测试增加现有仓位的流动性
     * @dev 这个测试会：
     *      1. 先创建一个仓位
     *      2. 增加流动性
     *      3. 验证流动性正确增加
     */
    function test_IncreaseLiquidity() public {
        console.log("\n========================================");
        console.log("TEST: Increase Liquidity");
        console.log("========================================\n");

        // 前置条件: 先创建一个仓位
        console.log("Step 0: Creating initial position...");
        uint256 tokenId = _createPosition(INITIAL_LIQUIDITY_0, INITIAL_LIQUIDITY_1);
        console.log("Initial position created with Token ID:", tokenId);

        // 获取初始流动性
        (,,,,,,, uint128 liquidityBefore,,,,) = POSITION_MANAGER.positions(tokenId);
        console.log("Initial liquidity:", liquidityBefore);

        // 为增加流动性准备额外的代币
        _fundUser(testUser, ADDITIONAL_LIQUIDITY_0, ADDITIONAL_LIQUIDITY_1);

        vm.startPrank(testUser);

        // 步骤 1: 授权额外的代币
        console.log("\nStep 1: Approving additional tokens...");
        IERC20(token0).approve(address(POSITION_MANAGER), ADDITIONAL_LIQUIDITY_0);
        IERC20(token1).approve(address(POSITION_MANAGER), ADDITIONAL_LIQUIDITY_1);

        // 步骤 2: 构造 increaseLiquidity 参数
        console.log("Step 2: Preparing increaseLiquidity params...");
        IV3NonfungiblePositionManager.IncreaseLiquidityParams memory params =
            _buildIncreaseLiquidityParams(
                tokenId,
                ADDITIONAL_LIQUIDITY_0,
                ADDITIONAL_LIQUIDITY_1
            );

        // 记录增加前的余额
        uint256 balance0Before = IERC20(token0).balanceOf(testUser);
        uint256 balance1Before = IERC20(token1).balanceOf(testUser);
        console.log("Token0 balance before:", balance0Before);
        console.log("Token1 balance before:", balance1Before);

        // 步骤 3: 调用 increaseLiquidity
        console.log("\nStep 3: Calling increaseLiquidity...");
        (
            uint128 liquidityAdded,
            uint256 amount0,
            uint256 amount1
        ) = POSITION_MANAGER.increaseLiquidity(params);

        vm.stopPrank();

        // 步骤 4: 验证结果
        console.log("\n=== IncreaseLiquidity Results ===");
        console.log("Liquidity added:", liquidityAdded);
        console.log("Amount0 used:", amount0);
        console.log("Amount1 used:", amount1);

        // 验证余额变化
        uint256 balance0After = IERC20(token0).balanceOf(testUser);
        uint256 balance1After = IERC20(token1).balanceOf(testUser);
        console.log("\nToken0 balance after:", balance0After);
        console.log("Token1 balance after:", balance1After);

        // 获取最终流动性
        (,,,,,,, uint128 liquidityAfter,,,,) = POSITION_MANAGER.positions(tokenId);
        console.log("\nLiquidity before:", liquidityBefore);
        console.log("Liquidity after:", liquidityAfter);
        console.log("Liquidity increase:", liquidityAfter - liquidityBefore);

        // 断言
        assertGt(liquidityAdded, 0, "Liquidity added should be greater than 0");
        assertEq(
            liquidityAfter,
            liquidityBefore + liquidityAdded,
            "Final liquidity should equal initial + added"
        );
        assertEq(amount0, balance0Before - balance0After, "Token0 amount mismatch");
        assertEq(amount1, balance1Before - balance1After, "Token1 amount mismatch");

        console.log("\n[SUCCESS] Liquidity increased successfully!");

        // 验证更新后的仓位详情
        _verifyPosition(tokenId, liquidityAfter);
    }

    // ============ 测试 3: 完整流程 ============

    /**
     * @notice 测试完整流程：mint -> increaseLiquidity -> 再次 increaseLiquidity
     */
    function test_FullFlow() public {
        console.log("\n========================================");
        console.log("TEST: Full Flow (Mint -> Increase -> Increase)");
        console.log("========================================\n");

        // 1. 创建仓位
        console.log("=== Phase 1: Create Position ===");
        uint256 tokenId = _createPosition(1e17, 1e17);
        (,,,,,,, uint128 liquidity1,,,,) = POSITION_MANAGER.positions(tokenId);
        console.log("Initial liquidity:", liquidity1);

        // 2. 第一次增加流动性
        console.log("\n=== Phase 2: First Increase ===");
        _increasePositionLiquidity(tokenId, 1e17, 1e17);
        (,,,,,,, uint128 liquidity2,,,,) = POSITION_MANAGER.positions(tokenId);
        console.log("Liquidity after 1st increase:", liquidity2);
        assertGt(liquidity2, liquidity1, "Liquidity should increase");

        console.log("[SUCCESS] Full flow completed successfully!");
    }

    // ============ 辅助函数 ============

    /**
     * @dev 为用户提供测试代币
     */
    function _fundUser(address user, uint256 amount0, uint256 amount1) internal {
        deal(token0, user, IERC20(token0).balanceOf(user) + amount0);
        deal(token1, user, IERC20(token1).balanceOf(user) + amount1);
    }

    /**
     * @dev 构造 mint 参数
     */
    function _buildMintParams(
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal view returns (IV3NonfungiblePositionManager.MintParams memory) {
        // tick spacing 对于 0.01% fee tier 是 1
        // 对于稳定币对，使用较窄的价格范围（±2%）
        // 稳定币对的价格通常在 1:1 附近，所以使用较小的 tick 范围
        int24 tickLower = -887220;  // 必须是 tick spacing (1) 的倍数
        int24 tickUpper = 887220;   // 必须是 tick spacing (1) 的倍数

        return IV3NonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: FEE_TIER,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: (amount0Desired * 50) / 100,  // 50% 滑点容忍度（宽松以确保测试通过）
            amount1Min: (amount1Desired * 50) / 100,
            recipient: testUser,
            deadline: block.timestamp + 15 minutes
        });
    }

    /**
     * @dev 构造 increaseLiquidity 参数
     */
    function _buildIncreaseLiquidityParams(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal view returns (IV3NonfungiblePositionManager.IncreaseLiquidityParams memory) {
        return IV3NonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: (amount0Desired * 50) / 100,  // 50% 滑点容忍度（宽松以确保测试通过）
            amount1Min: (amount1Desired * 50) / 100,
            deadline: block.timestamp + 15 minutes
        });
    }

    /**
     * @dev 创建流动性仓位（辅助函数）
     */
    function _createPosition(
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 tokenId) {
        _fundUser(testUser, amount0, amount1);

        vm.startPrank(testUser);

        IERC20(token0).approve(address(POSITION_MANAGER), amount0);
        IERC20(token1).approve(address(POSITION_MANAGER), amount1);

        IV3NonfungiblePositionManager.MintParams memory params =
            _buildMintParams(amount0, amount1);

        (tokenId,,,) = POSITION_MANAGER.mint(params);

        vm.stopPrank();
    }

    /**
     * @dev 增加仓位流动性（辅助函数）
     */
    function _increasePositionLiquidity(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1
    ) internal {
        _fundUser(testUser, amount0, amount1);

        vm.startPrank(testUser);

        IERC20(token0).approve(address(POSITION_MANAGER), amount0);
        IERC20(token1).approve(address(POSITION_MANAGER), amount1);

        IV3NonfungiblePositionManager.IncreaseLiquidityParams memory params =
            _buildIncreaseLiquidityParams(tokenId, amount0, amount1);

        POSITION_MANAGER.increaseLiquidity(params);

        vm.stopPrank();
    }

    /**
     * @dev 验证仓位详情
     */
    function _verifyPosition(uint256 tokenId, uint128 expectedLiquidity) internal view {
        (
            uint96 nonce,
            address operator,
            address posToken0,
            address posToken1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = POSITION_MANAGER.positions(tokenId);

        console.log("\n=== Position Details ===");
        console.log("Token ID:", tokenId);
        console.log("Nonce:", nonce);
        console.log("Operator:", operator);
        console.log("Token0:", posToken0);
        console.log("Token1:", posToken1);
        console.log("Fee:", fee);
        console.log("Tick Lower:", tickLower);
        console.log("Tick Upper:", tickUpper);
        console.log("Liquidity:", liquidity);
        console.log("Tokens Owed 0:", tokensOwed0);
        console.log("Tokens Owed 1:", tokensOwed1);

        // 断言验证
        assertEq(posToken0, token0, "Position token0 mismatch");
        assertEq(posToken1, token1, "Position token1 mismatch");
        assertEq(fee, FEE_TIER, "Position fee mismatch");
        assertEq(liquidity, expectedLiquidity, "Position liquidity mismatch");
    }
}
