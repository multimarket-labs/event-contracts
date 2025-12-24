// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IV3NonfungiblePositionManager} from "../src/interfaces/staking/pancake/IV3NonfungiblePositionManager.sol";

/**
 * @title AddLiquidityFlow
 * @notice 真实上链脚本：在 PancakeSwap V3 上添加流动性
 * @dev 执行完整流程：mint -> increaseLiquidity -> increaseLiquidity
 * 
 * ⚠️  警告：这会在真实的 BSC 主网上执行！
 * 
 * 使用前确保：
 * 1. 钱包有足够的 BNB 支付 gas 费用（约 0.01 BNB）
 * 2. 钱包有足够的 USDT 和 BUSD 代币
 * 3. 设置了正确的私钥环境变量
 * 
 * 运行方式：
 * 
 * 1. 设置环境变量：
 *    export PRIVATE_KEY=你的私钥
 *    export RPC_URL=https://bsc-dataseed.binance.org/
 * 
 * 2. 模拟运行（不上链，安全）：
 *    forge script script/AddLiquidityFlow.s.sol \
 *      --rpc-url $RPC_URL \
 *      -vvvv
 * 
 * 3. 真实执行（会上链！）：
 *    forge script script/AddLiquidityFlow.s.sol \
 *      --rpc-url $RPC_URL \
 *      --broadcast \
 *      --private-key $PRIVATE_KEY \
 *      -vvvv
 */
contract AddLiquidityFlow is Script {
    
    // ============ 配置参数 ============
    
    // PancakeSwap V3 Position Manager (BSC Mainnet)
    // 正确的 Position Manager 地址（不是池子地址！）
    IV3NonfungiblePositionManager constant POSITION_MANAGER = 
        IV3NonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);
    
    // 代币地址
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    
    // 流动性数量（可根据需要调整）
    uint256 constant INITIAL_AMOUNT_0 = 0.1e18;  // 0.1 USDT
    uint256 constant INITIAL_AMOUNT_1 = 0.1e18;  // 0.1 BUSD
    uint256 constant INCREASE_AMOUNT_0 = 0.1e18; // 0.1 USDT
    uint256 constant INCREASE_AMOUNT_1 = 0.1e18; // 0.1 BUSD
    
    // 费率
    uint24 constant FEE_TIER = 100; // 0.01%
    
    // 滑点容忍度 (50% = 较宽松)
    uint256 constant SLIPPAGE_TOLERANCE = 50; // 50%
    
    // ============ 状态变量 ============
    
    address deployer;
    address token0;
    address token1;
    uint256 tokenId;
    
    // ============ 主函数 ============
    
    function run() external {
        // 获取部署者地址
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        
        console.log("\n========================================");
        console.log("PancakeSwap V3 Add Liquidity Flow");
        console.log("========================================\n");
        
        console.log("Deployer:", deployer);
        console.log("Position Manager:", address(POSITION_MANAGER));
        
        // 确保 token0 < token1
        (token0, token1) = USDT < BUSD ? (USDT, BUSD) : (BUSD, USDT);
        console.log("Token0:", token0);
        console.log("Token1:", token1);
        console.log("Fee Tier:", FEE_TIER, "(0.01%)");
        
        // 检查余额
        _checkBalances();
        
        // 开始广播交易
        vm.startBroadcast();
        
        // Phase 1: 创建初始仓位
        console.log("\n=== Phase 1: Create Initial Position ===");
        tokenId = _mintPosition(INITIAL_AMOUNT_0, INITIAL_AMOUNT_1);
        uint128 liquidity1 = _getLiquidity(tokenId);
        console.log("   Position created!");
        console.log("   Token ID:", tokenId);
        console.log("   Initial liquidity:", liquidity1);
        
        // Phase 2: 第一次增加流动性
        console.log("\n=== Phase 2: First Increase ===");
        _increaseLiquidity(tokenId, INCREASE_AMOUNT_0, INCREASE_AMOUNT_1);
        uint128 liquidity2 = _getLiquidity(tokenId);
        console.log("   Liquidity increased!");
        console.log("   New liquidity:", liquidity2);
        console.log("   Increase:", liquidity2 - liquidity1);
        
        vm.stopBroadcast();
        
        // 最终总结
        console.log("\n========================================");
        console.log(" Flow completed successfully!");
        console.log("========================================");
        console.log("Token ID:", tokenId);
        console.log("View on PancakeSwap:");
        console.log("https://pancakeswap.finance/liquidity/positions/", tokenId);
        console.log("\nView on BSCScan:");
        console.log("https://bscscan.com/nft/0x46A15B0b27311cedF172AB29E4f4766fbE7F4364/", tokenId);
    }
    
    // ============ 内部函数 ============
    
    /**
     * @notice 检查钱包余额
     */
    function _checkBalances() internal view {
        console.log("\n=== Checking Balances ===");
        
        uint256 token0Balance = IERC20(token0).balanceOf(deployer);
        uint256 token1Balance = IERC20(token1).balanceOf(deployer);
        
        console.log("Token0 balance:", token0Balance / 1e18);
        console.log("Token1 balance:", token1Balance / 1e18);
        
        // 计算所需金额
        uint256 totalAmount0Needed = INITIAL_AMOUNT_0 + INCREASE_AMOUNT_0;
        uint256 totalAmount1Needed = INITIAL_AMOUNT_1 + INCREASE_AMOUNT_1;
        
        // 注意：在 forge script 模拟模式下，deployer.balance 可能为 0
        // 真实执行时会自动检查 gas，所以这里只检查代币余额
        require(token0Balance >= totalAmount0Needed, "Insufficient Token0");
        require(token1Balance >= totalAmount1Needed, "Insufficient Token1");
        
        console.log(" Balance check passed!");
        console.log(" Note: BNB balance will be checked during actual broadcast");
    }
    
    /**
     * @notice 创建新的流动性仓位
     */
    function _mintPosition(
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal returns (uint256) {
        // 授权代币
        IERC20(token0).approve(address(POSITION_MANAGER), amount0Desired);
        IERC20(token1).approve(address(POSITION_MANAGER), amount1Desired);
        
        // 构造 mint 参数
        IV3NonfungiblePositionManager.MintParams memory params = 
            IV3NonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE_TIER,
                tickLower: -887220,
                tickUpper: 887220,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: (amount0Desired * SLIPPAGE_TOLERANCE) / 100,
                amount1Min: (amount1Desired * SLIPPAGE_TOLERANCE) / 100,
                recipient: deployer,
                deadline: block.timestamp + 15 minutes
            });
        
        // 调用 mint
        (uint256 newTokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = 
            POSITION_MANAGER.mint(params);
        
        console.log("   Amount0 used:", amount0);
        console.log("   Amount1 used:", amount1);
        console.log("   Liquidity:", liquidity);
        
        return newTokenId;
    }
    
    /**
     * @notice 增加流动性
     */
    function _increaseLiquidity(
        uint256 _tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal {
        // 授权代币
        IERC20(token0).approve(address(POSITION_MANAGER), amount0Desired);
        IERC20(token1).approve(address(POSITION_MANAGER), amount1Desired);
        
        // 构造参数
        IV3NonfungiblePositionManager.IncreaseLiquidityParams memory params = 
            IV3NonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: _tokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: (amount0Desired * SLIPPAGE_TOLERANCE) / 100,
                amount1Min: (amount1Desired * SLIPPAGE_TOLERANCE) / 100,
                deadline: block.timestamp + 15 minutes
            });
        
        // 调用 increaseLiquidity
        (uint128 liquidityAdded, uint256 amount0, uint256 amount1) = 
            POSITION_MANAGER.increaseLiquidity(params);
        
        console.log("   Amount0 used:", amount0);
        console.log("   Amount1 used:", amount1);
        console.log("   Liquidity added:", liquidityAdded);
    }
    
    /**
     * @notice 获取仓位流动性
     */
    function _getLiquidity(uint256 _tokenId) internal view returns (uint128) {
        (,,,,,,, uint128 liquidity,,,,) = POSITION_MANAGER.positions(_tokenId);
        return liquidity;
    }
}

