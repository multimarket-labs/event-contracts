// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IV3NonfungiblePositionManager} from "../src/interfaces/staking/pancake/IV3NonfungiblePositionManager.sol";

/**
 * @title IncreaseLiquidity
 * @notice 向已有的 PancakeSwap V3 流动性仓位添加更多流动性
 * @dev 只执行 increaseLiquidity 操作，不创建新仓位
 * 
 * ⚠️  警告：这会在真实的 BSC 主网上执行！
 * 
 * 使用前确保：
 * 1. 你已经有一个流动性仓位（Token ID）
 * 2. 钱包有足够的 BNB 支付 gas 费用（约 0.005 BNB）
 * 3. 钱包有足够的代币
 * 4. 设置了正确的环境变量
 * 
 * 运行方式：
 * 
 * 1. 设置环境变量：
 *    export PRIVATE_KEY=你的私钥
 *    export DEPLOYER_ADDRESS=0x你的钱包地址
 *    export TOKEN_ID=你的仓位ID（例如：6103813）
 * 
 * 2. 模拟运行（不上链，安全）：
 *    forge script script/IncreaseLiquidity.s.sol \
 *      --rpc-url https://bsc-dataseed.binance.org/ \
 *      -vvvv
 * 
 * 3. 真实执行（会上链！）：
 *    forge script script/IncreaseLiquidity.s.sol \
 *      --rpc-url https://bsc-dataseed.binance.org/ \
 *      --broadcast \
 *      --private-key $PRIVATE_KEY \
 *      -vvvv
 */
contract IncreaseLiquidity is Script {
    
    // ============ 配置参数 ============
    
    // PancakeSwap V3 Position Manager (BSC Mainnet)
    IV3NonfungiblePositionManager constant POSITION_MANAGER = 
        IV3NonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);
    
    // 代币地址
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    
    // 要添加的流动性数量（可根据需要调整）
    uint256 constant AMOUNT_0 = 0.1e18;  // 0.1 USDT
    uint256 constant AMOUNT_1 = 0.1e18;  // 0.1 BUSD
    
    // 滑点容忍度 (50% = 较宽松)
    uint256 constant SLIPPAGE_TOLERANCE = 50; // 50%
    
    // ============ 状态变量 ============
    
    address deployer;
    address token0;
    address token1;
    uint256 tokenId;
    
    // ============ 主函数 ============
    
    function run() external {
        // 获取配置
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        tokenId = vm.envUint("TOKEN_ID");
        
        console.log("\n========================================");
        console.log("PancakeSwap V3 - Increase Liquidity");
        console.log("========================================\n");
        
        console.log("Deployer:", deployer);
        console.log("Position Manager:", address(POSITION_MANAGER));
        console.log("Token ID:", tokenId);
        
        // 验证 Token ID 的所有权
        _verifyOwnership();
        
        // 获取仓位信息
        _getPositionInfo();
        
        // 确保 token0 < token1
        (token0, token1) = USDT < BUSD ? (USDT, BUSD) : (BUSD, USDT);
        console.log("Token0:", token0);
        console.log("Token1:", token1);
        
        // 检查余额
        _checkBalances();
        
        // 开始广播交易
        vm.startBroadcast();
        
        console.log("\n=== Adding Liquidity ===");
        
        // 获取增加前的流动性
        uint128 liquidityBefore = _getLiquidity(tokenId);
        console.log("Current liquidity:", liquidityBefore);
        
        // 增加流动性
        (uint128 liquidityAdded, uint256 amount0Used, uint256 amount1Used) = 
            _increaseLiquidity(tokenId, AMOUNT_0, AMOUNT_1);
        
        vm.stopBroadcast();
        
        // 获取增加后的流动性
        uint128 liquidityAfter = _getLiquidity(tokenId);
        
        // 显示结果
        console.log("\n========================================");
        console.log("Success! Liquidity Increased");
        console.log("========================================");
        console.log("Liquidity added:", liquidityAdded);
        console.log("Amount0 used:", amount0Used);
        console.log("Amount1 used:", amount1Used);
        console.log("Liquidity before:", liquidityBefore);
        console.log("Liquidity after:", liquidityAfter);
        console.log("Total increase:", liquidityAfter - liquidityBefore);
        console.log("\nView on PancakeSwap:");
        console.log("https://pancakeswap.finance/liquidity/positions/", tokenId);
        console.log("\nView on BSCScan:");
        console.log("https://bscscan.com/nft/0x46A15B0b27311cedF172AB29E4f4766fbE7F4364/", tokenId);
    }
    
    // ============ 内部函数 ============
    
    /**
     * @notice 验证 Token ID 的所有权
     */
    function _verifyOwnership() internal view {
        address owner = POSITION_MANAGER.ownerOf(tokenId);
        
        console.log("\n=== Verifying Ownership ===");
        console.log("Position owner:", owner);
        
        if (owner != deployer) {
            console.log("WARNING: You are not the owner of this position!");
            console.log("Owner:", owner);
            console.log("Your address:", deployer);
            revert("Not position owner");
        }
        
        console.log("Ownership verified!");
    }
    
    /**
     * @notice 获取仓位信息
     */
    function _getPositionInfo() internal view {
        (
            ,
            ,
            address posToken0,
            address posToken1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,
        ) = POSITION_MANAGER.positions(tokenId);
        
        console.log("\n=== Position Info ===");
        console.log("Token0:", posToken0);
        console.log("Token1:", posToken1);
        console.log("Fee tier:", fee);
        console.log("Tick lower:", tickLower);
        console.log("Tick upper:", tickUpper);
        console.log("Current liquidity:", liquidity);
    }
    
    /**
     * @notice 检查钱包余额
     */
    function _checkBalances() internal view {
        console.log("\n=== Checking Balances ===");
        
        uint256 token0Balance = IERC20(token0).balanceOf(deployer);
        uint256 token1Balance = IERC20(token1).balanceOf(deployer);
        
        console.log("Token0 balance:", token0Balance / 1e18);
        console.log("Token1 balance:", token1Balance / 1e18);
        
        require(token0Balance >= AMOUNT_0, "Insufficient Token0");
        require(token1Balance >= AMOUNT_1, "Insufficient Token1");
        
        console.log("Balance check passed!");
    }
    
    /**
     * @notice 增加流动性
     */
    function _increaseLiquidity(
        uint256 _tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal returns (uint128 liquidityAdded, uint256 amount0, uint256 amount1) {
        // 授权代币（使用较大的额度以避免重复授权）
        console.log("Approving tokens...");
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
        console.log("Calling increaseLiquidity...");
        (liquidityAdded, amount0, amount1) = POSITION_MANAGER.increaseLiquidity(params);
        
        console.log("Transaction successful!");
    }
    
    /**
     * @notice 获取仓位流动性
     */
    function _getLiquidity(uint256 _tokenId) internal view returns (uint128) {
        (,,,,,,, uint128 liquidity,,,,) = POSITION_MANAGER.positions(_tokenId);
        return liquidity;
    }
}

