// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/interfaces/staking/pancake/IPancakeV3Pool.sol";
import "../src/interfaces/staking/pancake/IPancakeV3Factory.sol";
import "../src/interfaces/staking/pancake/IPancakeV3SwapCallback.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// 辅助合约：处理 swap 回调
contract SwapHelper is IPancakeV3SwapCallback {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function executeSwap(
        address pool,
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external returns (int256 amount0, int256 amount1) {
        require(msg.sender == owner, "Not owner");
        return IPancakeV3Pool(pool).swap(
            recipient,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            abi.encode(pool)
        );
    }

    function pancakeV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        address pool = abi.decode(data, (address));
        require(msg.sender == pool, "Invalid caller");

        address token0 = IPancakeV3Pool(pool).token0();
        address token1 = IPancakeV3Pool(pool).token1();

        // 从 owner 转账到池子
        if (amount0Delta > 0) {
            IERC20(token0).transferFrom(owner, pool, uint256(amount0Delta));
        }

        if (amount1Delta > 0) {
            IERC20(token1).transferFrom(owner, pool, uint256(amount1Delta));
        }
    }
}

contract SwapCakeToUsdt is Script {
    IPancakeV3Factory constant FACTORY = IPancakeV3Factory(0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865);

    address constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    address public deployer;
    
    function run() external {
        // 从环境变量读取私钥（必须是 0x 开头的十六进制格式）
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 swapAmount = 0.1e18;
        
        deployer = vm.addr(deployerPrivateKey);
        
        console.log("========================================");
        console.log("PancakeSwap V3 - CAKE to USDT Swap");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Swap Amount: %s.%s CAKE", swapAmount / 1e18, (swapAmount % 1e18) / 1e12);
        console.log("");
        
        // 查找池子
        uint24[4] memory fees = [uint24(100), 500, 2500, 10000];
        address pool;
        uint24 selectedFee;
        
        for (uint256 i = 0; i < fees.length; i++) {
            address potentialPool = FACTORY.getPool(CAKE, USDT, fees[i]);
            if (potentialPool != address(0)) {
                pool = potentialPool;
                selectedFee = fees[i];
                break;
            }
        }
        
        require(pool != address(0), "Pool not found");
        console.log("Pool:", pool);
        console.log("Fee:", selectedFee);
        console.log("");
        
        // 检查余额
        uint256 cakeBalance = IERC20(CAKE).balanceOf(deployer);
        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(deployer);
        uint256 bnbBalance = deployer.balance;

        console.log("CAKE Balance: %s.%s CAKE", cakeBalance / 1e18, (cakeBalance % 1e18) / 1e12);
        console.log("USDT Balance: %s.%s USDT", usdtBalanceBefore / 1e18, (usdtBalanceBefore % 1e18) / 1e12);
        console.log("BNB Balance: %s.%s BNB", bnbBalance / 1e18, (bnbBalance % 1e18) / 1e12);
        console.log("");
        
        require(cakeBalance >= swapAmount, "Insufficient CAKE");
        require(bnbBalance >= 0.01 ether, "Insufficient BNB for gas");
        
        // 查询价格
        IPancakeV3Pool v3Pool = IPancakeV3Pool(pool);
        (uint160 sqrtPriceX96,,,,,,) = v3Pool.slot0();
        uint256 price = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * 1e18) / (2 ** 192);

        console.log("Current Price: %s.%s USDT per CAKE", price / 1e18, (price % 1e18) / 1e12);
        console.log("");

        // 执行 Swap
        console.log("=== Executing Swap ===");

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署 SwapHelper 合约
        SwapHelper helper = new SwapHelper();
        console.log("SwapHelper deployed at:", address(helper));

        // 2. 授权 helper 合约可以转移 CAKE
        IERC20(CAKE).approve(address(helper), swapAmount);
        console.log("Approved CAKE to SwapHelper");

        // 3. 通过 helper 执行 swap
        bool zeroForOne = CAKE < USDT;

        // 设置价格限制：允许最多 10% 的价格滑点
        uint160 sqrtPriceLimitX96;
        if (zeroForOne) {
            // 向下 swap，价格下降，使用当前价格的 90% 作为限制
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 95) / 100);
        } else {
            // 向上 swap，价格上升，使用当前价格的 110% 作为限制
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 105) / 100);
        }

        console.log("sqrtPriceLimitX96:", sqrtPriceLimitX96);

        (int256 amount0, int256 amount1) = helper.executeSwap(
            pool,
            deployer,  // recipient: deployer 接收 USDT
            zeroForOne,
            int256(swapAmount),
            sqrtPriceLimitX96
        );

        vm.stopBroadcast();
        
        console.log("amount0:", amount0);
        console.log("amount1:", amount1);
        console.log("");
        
        // 验证结果
        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(deployer);
        uint256 usdtReceived = usdtBalanceAfter - usdtBalanceBefore;
        
        console.log("========================================");
        console.log("USDT Received: %s.%s USDT", usdtReceived / 1e18, (usdtReceived % 1e18) / 1e12);
        console.log("Exchange Rate: %s.%s USDT/CAKE", (usdtReceived * 1e18 / swapAmount) / 1e18, ((usdtReceived * 1e18 / swapAmount) % 1e18) / 1e12);
        console.log("========================================");
    }
}
