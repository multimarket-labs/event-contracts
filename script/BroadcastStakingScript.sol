// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IPancakeV2Factory} from "../src/interfaces/staking/pancake/IPancakeV2Factory.sol";
import {IPancakeV2Router} from "../src/interfaces/staking/pancake/IPancakeV2Router.sol";
import {IPancakeV2Pair} from "../src/interfaces/staking/pancake/IPancakeV2Pair.sol";

import {EmptyContract} from "../src/utils/EmptyContract.sol";
import {ChooseMeToken} from "../src/token/ChooseMeToken.sol";
import {IChooseMeToken} from "../src/interfaces/token/IChooseMeToken.sol";
import {DaoRewardManager} from "../src/token/allocation/DaoRewardManager.sol";
import {FomoTreasureManager} from "../src/token/allocation/FomoTreasureManager.sol";
import {NodeManager} from "../src/staking/NodeManager.sol";
import {StakingManager} from "../src/staking/StakingManager.sol";
import {EventFundingManager} from "../src/staking/EventFundingManager.sol";
import {SubTokenFundingManager} from "../src/staking/SubTokenFundingManager.sol";

interface IPancakeRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

contract TestUSDT is ERC20 {
    constructor() ERC20("TestUSDT", "USDT") {
        _mint(msg.sender, 10000000 * 10 ** 18);
    }
}

// forge script BroadcastStakingScript --slow --multi --rpc-url https://bsc-dataseed.binance.org --broadcast

contract BroadcastStakingScript is Script {
    ERC20 public usdt;
    ChooseMeToken public chooseMeToken;
    NodeManager public nodeManager;
    StakingManager public stakingManager;
    DaoRewardManager public daoRewardManager;
    FomoTreasureManager public fomoTreasureManager;
    EventFundingManager public eventFundingManager;
    SubTokenFundingManager public subTokenFundingManager;
    IPancakeRouter public pancakeRouter;

    uint256 cmtDecimals = 10 ** 6;
    uint256 usdtDecimals = 10 ** 18;

    uint256 deployerPrivateKey;
    uint256 initPoolPrivateKey;
    uint256 user2PrivateKey;
    uint256 user3PrivateKey;
    uint256 user4PrivateKey;
    uint256 user5PrivateKey;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory mnemonic = vm.envString("MNEMONIC");
        initPoolPrivateKey = vm.deriveKey(mnemonic, 1);
        user2PrivateKey = vm.deriveKey(mnemonic, 2);
        user3PrivateKey = vm.deriveKey(mnemonic, 3);
        user4PrivateKey = vm.deriveKey(mnemonic, 4);
        user5PrivateKey = vm.deriveKey(mnemonic, 5);

        initContracts();

        // initChooseMeToken();
        // transferGasFee(initPoolPrivateKey);
        // transfer();
        // addLiquidity();

        distributeNodeRewards(deployerPrivateKey, 0x7f345497612FbA3DFb923b422D67108BB5894EA6, 1000 * cmtDecimals, 0);
        createLiquidityProviderReward(
            deployerPrivateKey, 0x7f345497612FbA3DFb923b422D67108BB5894EA6, 1000 * cmtDecimals, 0
        );
    }

    function initContracts() internal {
        usdt = ERC20(payable(0xC6b745cC58B2682F6b5a23f5237F13A4E9B1Aa8a));
        chooseMeToken = ChooseMeToken(payable(0x9c160Fa55E01Ed9d3D00F69F9F3D6f3755d64484));
        daoRewardManager = DaoRewardManager(payable(0x3584CB390400B717B575a4026c2C55b066EAE55C));
        eventFundingManager = EventFundingManager(payable(0x3243464Cd3fa6a469C3518F40146A608B6b26f39));
        fomoTreasureManager = FomoTreasureManager(payable(0xbabA1933619Fd156e87Da82a1b3f6660514bB8e8));
        nodeManager = NodeManager(payable(0xe3d2de76bdB390A7e9c0500efFC35B2266dfeBeB));
        stakingManager = StakingManager(payable(0x35Fa1789EDcD0ED819FDd663e0F563e5a48475EF));
        subTokenFundingManager = SubTokenFundingManager(payable(0x8365b9BC8e965c08dcB8bcCcBECA02B8760e90C4));
        pancakeRouter = IPancakeRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E); // PancakeSwap Router V2
        console.log("Contracts initialized");
    }

    function initChooseMeToken() internal {
        if (chooseMeToken.balanceOf(address(daoRewardManager)) > 0) return;

        vm.startBroadcast(deployerPrivateKey);

        IChooseMeToken.ChooseMePool memory pools = IChooseMeToken.ChooseMePool({
            nodePool: vm.rememberKey(deployerPrivateKey),
            daoRewardPool: address(daoRewardManager),
            airdropPool: vm.rememberKey(initPoolPrivateKey),
            techRewardsPool: vm.rememberKey(initPoolPrivateKey),
            ecosystemPool: vm.rememberKey(initPoolPrivateKey),
            foundingStrategyPool: vm.rememberKey(initPoolPrivateKey),
            marketingDevelopmentPool: vm.rememberKey(initPoolPrivateKey),
            subTokenPool: address(subTokenFundingManager)
        });
        chooseMeToken.setPoolAddress(pools);
        console.log("Pool addresses set");

        // Execute pool allocation
        chooseMeToken.poolAllocate();
        console.log("Pool allocation completed");
        console.log("Total Supply:", chooseMeToken.totalSupply() / cmtDecimals, "CMT");

        vm.stopBroadcast();
    }

    function addLiquidity() internal {
        address deployer = vm.rememberKey(deployerPrivateKey);
        uint256 cmtBalance = chooseMeToken.balanceOf(deployer);
        uint256 usdtBalance = usdt.balanceOf(deployer);

        if (cmtBalance == 0 || usdtBalance == 0) {
            console.log("Insufficient balance for adding liquidity");
            return;
        }

        vm.startBroadcast(deployerPrivateKey);

        // 设置添加流动性的数量（可以根据需要调整）
        uint256 cmtAmount = 1_000_000 * cmtDecimals;
        uint256 usdtAmount = 100_000 * usdtDecimals;

        // 批准代币给路由器
        chooseMeToken.approve(address(pancakeRouter), cmtAmount);
        usdt.approve(address(pancakeRouter), usdtAmount);
        console.log("Tokens approved for PancakeSwap Router");

        // 添加流动性
        (uint256 amountA, uint256 amountB, uint256 liquidity) = pancakeRouter.addLiquidity(
            address(chooseMeToken),
            address(usdt),
            cmtAmount,
            usdtAmount,
            0, // amountAMin (可以设置滑点保护)
            0, // amountBMin (可以设置滑点保护)
            deployer, // LP tokens 接收地址
            block.timestamp + 300 // 5分钟后过期
        );

        console.log("Liquidity added successfully");
        console.log("CMT amount:", amountA / cmtDecimals);
        console.log("USDT amount:", amountB / usdtDecimals);
        console.log("LP tokens:", liquidity);

        vm.stopBroadcast();
    }

    function transferGasFee(uint256 toPrivateKey) internal {
        address toAddress = vm.rememberKey(toPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        payable(toAddress).transfer(0.001 ether);
        vm.stopBroadcast();
    }

    function transfer() internal {
        vm.startBroadcast(initPoolPrivateKey);
        usdt.transfer(0xD837FF8cb366D1f9ebDB0659b066b709804D52bc, 100000 * usdtDecimals);
        chooseMeToken.transfer(0xD837FF8cb366D1f9ebDB0659b066b709804D52bc, 100000 * cmtDecimals);

        usdt.transfer(0x7f345497612FbA3DFb923b422D67108BB5894EA6, 100000 * usdtDecimals);
        chooseMeToken.transfer(0x7f345497612FbA3DFb923b422D67108BB5894EA6, 100000 * cmtDecimals);

        usdt.transfer(0xcCA370146cabEb663a277c80db355aAf749fa3eb, 100000 * usdtDecimals);
        chooseMeToken.transfer(0xcCA370146cabEb663a277c80db355aAf749fa3eb, 100000 * cmtDecimals);
        vm.stopBroadcast();
    }

    function swap(uint256 userPrivateKey, address token0, address token1, uint256 amount0) internal {
        address userAddress = vm.rememberKey(userPrivateKey);
        address initPoolAddress = vm.rememberKey(initPoolPrivateKey);
        address deployerAddress = vm.rememberKey(deployerPrivateKey);

        // 步骤 1: 从 initPoolPrivateKey 将 token0 转移到用户地址
        vm.startBroadcast(initPoolPrivateKey);
        ERC20(token0).transfer(userAddress, amount0);
        console.log("Transferred token0 to user address");
        console.log("Amount:", amount0);
        vm.stopBroadcast();

        // 步骤 2: 预估交易 gas 费用
        uint256 estimatedGas = 300000; // 预估的 gas limit
        uint256 gasPrice = tx.gasprice;
        uint256 gasCost = estimatedGas * gasPrice;

        console.log("Estimated gas:", estimatedGas);
        console.log("Gas price:", gasPrice);
        console.log("Estimated gas cost:", gasCost);

        // 步骤 3: 从 deployerPrivateKey 转移 gas 费用（BNB）到用户地址
        vm.startBroadcast(deployerPrivateKey);
        payable(userAddress).transfer(gasCost);
        console.log("Transferred gas fee to user address");
        console.log("Gas fee amount (BNB):", gasCost);
        vm.stopBroadcast();

        // 步骤 4: 使用用户私钥执行 swap 交易
        vm.startBroadcast(userPrivateKey);

        // 批准 token0 给路由器
        ERC20(token0).approve(address(pancakeRouter), amount0);
        console.log("Token0 approved for router");

        // 准备 swap 路径
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;

        // 执行 swap
        uint256[] memory amounts = IPancakeV2Router(address(pancakeRouter))
            .swapExactTokensForTokens(
                amount0,
                0, // amountOutMin (可以设置滑点保护)
                path,
                userAddress,
                block.timestamp + 300 // 5分钟后过期
            );

        console.log("Swap executed successfully");
        console.log("Amount in:", amounts[0]);
        console.log("Amount out:", amounts[1]);

        vm.stopBroadcast();
    }

    /**
     * @dev 绑定邀请人
     * @param userPrivateKey 用户私钥
     * @param inviterAddress 邀请人地址
     */
    function bindInviter(uint256 userPrivateKey, address inviterAddress) internal {
        address userAddress = vm.rememberKey(userPrivateKey);

        console.log("--- Bind Inviter Test ---");
        console.log("User:", userAddress);
        console.log("Inviter:", inviterAddress);

        vm.startBroadcast(userPrivateKey);

        if (nodeManager.inviters(userAddress) == address(0)) {
            nodeManager.bindInviter(inviterAddress);
            console.log("Successfully bound inviter");
        } else {
            console.log("Inviter already set, skipping");
        }

        vm.stopBroadcast();
    }

    /**
     * @dev 购买节点
     * @param userPrivateKey 用户私钥
     * @param nodeAmount 节点金额（USDT）
     */
    function purchaseNode(uint256 userPrivateKey, uint256 nodeAmount) internal {
        address userAddress = vm.rememberKey(userPrivateKey);

        console.log("--- Purchase Node Test ---");
        console.log("User:", userAddress);
        console.log("Node Amount:", nodeAmount / usdtDecimals, "USDT");

        vm.startBroadcast(userPrivateKey);

        uint256 userUsdtBalance = usdt.balanceOf(userAddress);
        require(userUsdtBalance >= nodeAmount, "Insufficient USDT balance for node purchase");

        usdt.approve(address(nodeManager), nodeAmount);
        nodeManager.purchaseNode(nodeAmount);
        console.log("Node purchased successfully");

        vm.stopBroadcast();
    }

    /**
     * @dev 分发节点奖励
     * @param operatorPrivateKey 操作员私钥（需要有 distributeRewardManager 权限）
     * @param recipient 接收者地址
     * @param rewardAmount 奖励金额（CMT）
     * @param incomeType 收益类型（0 - 节点收益, 1 - 推广收益）
     */
    function distributeNodeRewards(
        uint256 operatorPrivateKey,
        address recipient,
        uint256 rewardAmount,
        uint8 incomeType
    ) internal {
        console.log("--- Distribute Node Rewards Test ---");
        console.log("Recipient:", recipient);
        console.log("Reward Amount:", rewardAmount / cmtDecimals, "CMT");
        console.log("Income Type:", incomeType);

        vm.startBroadcast(operatorPrivateKey);

        nodeManager.distributeRewards(recipient, rewardAmount, incomeType);
        console.log("Rewards distributed successfully");

        vm.stopBroadcast();
    }

    /**
     * @dev 领取节点奖励
     * @param userPrivateKey 用户私钥
     * @param claimAmount 领取金额（CMT）
     */
    function claimNodeReward(uint256 userPrivateKey, uint256 claimAmount) internal {
        address userAddress = vm.rememberKey(userPrivateKey);

        console.log("--- Claim Node Reward Test ---");
        console.log("User:", userAddress);
        console.log("Claim Amount:", claimAmount / cmtDecimals, "CMT");

        vm.startBroadcast(userPrivateKey);

        nodeManager.claimReward(claimAmount);
        console.log("Rewards claimed successfully");

        vm.stopBroadcast();
    }

    /**
     * @dev 添加流动性到 PancakeSwap（通过 NodeManager）
     * @param operatorPrivateKey 操作员私钥（需要有 distributeRewardManager 权限）
     * @param liquidityAmount 流动性金额（USDT）
     */
    function addLiquidityViaNode(uint256 operatorPrivateKey, uint256 liquidityAmount) internal {
        address operatorAddress = vm.rememberKey(operatorPrivateKey);

        console.log("--- Add Liquidity Test (NodeManager) ---");
        console.log("Operator:", operatorAddress);
        console.log("Liquidity Amount:", liquidityAmount / usdtDecimals, "USDT");

        vm.startBroadcast(operatorPrivateKey);

        uint256 usdtBalance = usdt.balanceOf(address(nodeManager));
        require(usdtBalance >= liquidityAmount, "Insufficient USDT balance for liquidity");

        nodeManager.addLiquidity(liquidityAmount);
        console.log("Liquidity added successfully");

        vm.stopBroadcast();
    }

    /**
     * @dev 添加流动性到 PancakeSwap（通过 StakingManager）
     * @param operatorPrivateKey 操作员私钥（需要有 stakingOperatorManager 权限）
     * @param liquidityAmount 流动性金额（USDT）
     */
    function addLiquidityViaStaking(uint256 operatorPrivateKey, uint256 liquidityAmount) internal {
        address operatorAddress = vm.rememberKey(operatorPrivateKey);

        console.log("--- Add Liquidity Test (StakingManager) ---");
        console.log("Operator:", operatorAddress);
        console.log("Liquidity Amount:", liquidityAmount / usdtDecimals, "USDT");

        vm.startBroadcast(operatorPrivateKey);

        uint256 usdtBalance = usdt.balanceOf(address(stakingManager));
        require(usdtBalance >= liquidityAmount, "Insufficient USDT balance for liquidity");

        stakingManager.addLiquidity(liquidityAmount);
        console.log("Liquidity added successfully");

        vm.stopBroadcast();
    }

    /**
     * @dev 流动性提供者质押存款
     * @param userPrivateKey 用户私钥
     * @param stakingAmount 质押金额（USDT，必须是 T1-T6 之一）
     */
    function liquidityProviderDeposit(uint256 userPrivateKey, uint256 stakingAmount) internal {
        address userAddress = vm.rememberKey(userPrivateKey);

        console.log("--- Liquidity Provider Deposit Test ---");
        console.log("User:", userAddress);
        console.log("Staking Amount:", stakingAmount / usdtDecimals, "USDT");

        vm.startBroadcast(userPrivateKey);

        uint256 userUsdtBalance = usdt.balanceOf(userAddress);
        require(userUsdtBalance >= stakingAmount, "Insufficient USDT balance for staking");

        usdt.approve(address(stakingManager), stakingAmount);
        stakingManager.liquidityProviderDeposit(stakingAmount);
        console.log("Liquidity provider deposit successful");

        vm.stopBroadcast();
    }

    /**
     * @dev 创建流动性提供者奖励
     * @param operatorPrivateKey 操作员私钥（需要有 stakingOperatorManager 权限）
     * @param lpAddress 流动性提供者地址
     * @param rewardAmount 奖励金额（CMT）
     * @param incomeType 收益类型（0-每日收益, 1-直推奖励, 2-团队奖励, 3-FOMO池奖励）
     */
    function createLiquidityProviderReward(
        uint256 operatorPrivateKey,
        address lpAddress,
        uint256 rewardAmount,
        uint8 incomeType
    ) internal {
        console.log("--- Create Liquidity Provider Reward Test ---");
        console.log("LP Address:", lpAddress);
        console.log("Reward Amount:", rewardAmount / cmtDecimals, "CMT");
        console.log("Income Type:", incomeType);

        vm.startBroadcast(operatorPrivateKey);

        stakingManager.createLiquidityProviderReward(lpAddress, rewardAmount, incomeType);
        console.log("Liquidity provider reward created successfully");

        vm.stopBroadcast();
    }

    /**
     * @dev 标记流动性提供者轮次质押结束
     * @param operatorPrivateKey 操作员私钥（需要有 stakingOperatorManager 权限）
     * @param lpAddress 流动性提供者地址
     * @param round 质押轮次
     */
    function liquidityProviderRoundStakingOver(uint256 operatorPrivateKey, address lpAddress, uint256 round) internal {
        console.log("--- Liquidity Provider Round Staking Over Test ---");
        console.log("LP Address:", lpAddress);
        console.log("Round:", round);

        vm.startBroadcast(operatorPrivateKey);

        stakingManager.liquidityProviderRoundStakingOver(lpAddress, round);
        console.log("Liquidity provider round staking marked as over");

        vm.stopBroadcast();
    }

    /**
     * @dev 流动性提供者领取奖励
     * @param userPrivateKey 用户私钥
     * @param claimAmount 领取金额（CMT）
     */
    function liquidityProviderClaimReward(uint256 userPrivateKey, uint256 claimAmount) internal {
        address userAddress = vm.rememberKey(userPrivateKey);

        console.log("--- Liquidity Provider Claim Reward Test ---");
        console.log("User:", userAddress);
        console.log("Claim Amount:", claimAmount / cmtDecimals, "CMT");

        vm.startBroadcast(userPrivateKey);

        stakingManager.liquidityProviderClaimReward(claimAmount);
        console.log("Liquidity provider reward claimed successfully");

        vm.stopBroadcast();
    }

    /**
     * @dev 交换 USDT 为底层代币并销毁
     * @param operatorPrivateKey 操作员私钥（需要有 stakingOperatorManager 权限）
     * @param swapAmount USDT 交换金额
     * @param subTokenAmount 转给 subTokenFundingManager 的 USDT 金额
     */
    function swapBurn(uint256 operatorPrivateKey, uint256 swapAmount, uint256 subTokenAmount) internal {
        address operatorAddress = vm.rememberKey(operatorPrivateKey);

        console.log("--- Swap and Burn Test ---");
        console.log("Operator:", operatorAddress);
        console.log("Swap Amount:", swapAmount / usdtDecimals, "USDT");
        console.log("SubToken Amount:", subTokenAmount / usdtDecimals, "USDT");

        vm.startBroadcast(operatorPrivateKey);

        uint256 usdtBalance = usdt.balanceOf(address(stakingManager));
        require(usdtBalance >= swapAmount + subTokenAmount, "Insufficient USDT balance in StakingManager");

        stakingManager.swapBurn(swapAmount, subTokenAmount);
        console.log("Swap and burn executed successfully");

        vm.stopBroadcast();
    }

    /**
     * @dev 流动性提供者完整流程集成测试
     */
    function integratedLiquidityProviderTest() internal {
        address user2Address = vm.rememberKey(user2PrivateKey);
        address deployerAddress = vm.rememberKey(deployerPrivateKey);

        console.log("=== Starting Integrated Liquidity Provider Test ===");

        // 1. 确保用户已绑定邀请人
        if (nodeManager.inviters(user2Address) == address(0)) {
            bindInviter(user2PrivateKey, deployerAddress);
        }

        // 2. 流动性提供者质押（T1级别: 100 USDT）
        uint256 t1Amount = 100 * usdtDecimals;
        liquidityProviderDeposit(user2PrivateKey, t1Amount);

        // 3. 创建流动性提供者奖励（需要 stakingOperatorManager 权限）
        // createLiquidityProviderReward(deployerPrivateKey, user2Address, 5 * cmtDecimals, 0);

        // 4. 领取奖励
        // liquidityProviderClaimReward(user2PrivateKey, 2 * cmtDecimals);

        // 5. 交换并销毁代币
        // swapBurn(deployerPrivateKey, 100 * usdtDecimals, 10 * usdtDecimals);

        console.log("=== Integrated Liquidity Provider Test Completed ===");
    }
}
