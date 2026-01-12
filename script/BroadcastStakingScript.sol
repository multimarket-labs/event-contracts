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

        transfer();
        // initChooseMeToken();
        // addLiquidity();
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

    function swapTransfer(uint256 userPrivateKey, address token0, address token1, uint256 amount0) internal {
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
}
