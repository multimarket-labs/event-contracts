// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/staking/pancake/IPancakeV2Router.sol";
import "../interfaces/staking/pancake/IPancakeV2Pair.sol";
import "../interfaces/staking/pancake/IPancakeV2Factory.sol";

/**
 * @title SwapV2Helper
 * @notice Helper library for PancakeSwap V2 operations
 * @dev Provides utility functions for swapping tokens using PancakeSwap V2
 *      V2 is more tolerant of transfer fees and doesn't require callbacks
 */
library SwapV2Helper {
    using SafeERC20 for IERC20;

    // PancakeSwap V2 addresses on BSC Mainnet
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    /**
     * @dev Swap token to USDT using PancakeSwap V2
     * @param tokenIn Input token address
     * @param usdt USDT token address
     * @param amountIn Amount of input token
     * @param recipient Recipient address
     * @return Amount of USDT received
     * @notice Uses swapExactTokensForTokensSupportingFeeOnTransferTokens to support tax tokens
     */
    function swapTokenToUsdt(
        address tokenIn,
        address usdt,
        uint256 amountIn,
        address recipient
    ) internal returns (uint256) {
        require(amountIn > 0, "SwapV2Helper: Amount must be greater than 0");

        // Check if pair exists
        address pair = getPair(tokenIn, usdt);
        require(pair != address(0), "SwapV2Helper: Pair does not exist");

        // Approve router to spend tokens
        IERC20(tokenIn).forceApprove(ROUTER, amountIn);

        // Create swap path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = usdt;

        // Get expected output amount (this will also check pair existence internally)
        uint256[] memory amounts = IPancakeV2Router(ROUTER).getAmountsOut(amountIn, path);
        uint256 amountOutMin = (amounts[1] * 95) / 100; // 5% slippage tolerance

        // Record balance before swap
        uint256 balanceBefore = IERC20(usdt).balanceOf(recipient);

        // Execute swap (using fee-on-transfer version to support tax tokens)
        IPancakeV2Router(ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            recipient,
            block.timestamp + 300
        );

        // Calculate actual amount received (important for fee-on-transfer tokens)
        uint256 balanceAfter = IERC20(usdt).balanceOf(recipient);
        uint256 usdtReceived = balanceAfter - balanceBefore;

        return usdtReceived;
    }

    /**
     * @dev Swap USDT to token using PancakeSwap V2
     * @param usdt USDT token address
     * @param tokenOut Output token address
     * @param amountIn Amount of USDT
     * @param recipient Recipient address
     * @return Amount of token received
     * @notice Uses swapExactTokensForTokensSupportingFeeOnTransferTokens to support tax tokens
     */
    function swapUsdtToToken(
        address usdt,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) internal returns (uint256) {
        require(amountIn > 0, "SwapV2Helper: Amount must be greater than 0");

        // Check if pair exists
        address pair = getPair(usdt, tokenOut);
        require(pair != address(0), "SwapV2Helper: Pair does not exist");

        // Approve router to spend USDT
        IERC20(usdt).forceApprove(ROUTER, amountIn);

        // Create swap path
        address[] memory path = new address[](2);
        path[0] = usdt;
        path[1] = tokenOut;

        // Get expected output amount (this will also check pair existence internally)
        uint256[] memory amounts = IPancakeV2Router(ROUTER).getAmountsOut(amountIn, path);
        uint256 amountOutMin = (amounts[1] * 95) / 100; // 5% slippage tolerance

        // Record balance before swap
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(recipient);

        // Execute swap (using fee-on-transfer version to support tax tokens)
        IPancakeV2Router(ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            recipient,
            block.timestamp + 300
        );

        // Calculate actual amount received (important for fee-on-transfer tokens)
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(recipient);
        uint256 tokenReceived = balanceAfter - balanceBefore;

        return tokenReceived;
    }

    /**
     * @dev Create a V2 pair if it doesn't exist
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return pair Address of the pair
     */
    function createPairIfNeeded(address tokenA, address tokenB) internal returns (address pair) {
        pair = IPancakeV2Factory(FACTORY).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = IPancakeV2Factory(FACTORY).createPair(tokenA, tokenB);
        }
        return pair;
    }

    /**
     * @dev Get the V2 pair address for two tokens
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return pair Address of the pair (returns address(0) if doesn't exist)
     */
    function getPair(address tokenA, address tokenB) internal view returns (address pair) {
        return IPancakeV2Factory(FACTORY).getPair(tokenA, tokenB);
    }

    /**
     * @dev Add liquidity to a V2 pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param amountADesired Amount of tokenA desired
     * @param amountBDesired Amount of tokenB desired
     * @param amountAMin Minimum amount of tokenA
     * @param amountBMin Minimum amount of tokenB
     * @param to Recipient of LP tokens
     * @return amountA Amount of tokenA added
     * @return amountB Amount of tokenB added
     * @return liquidity Amount of LP tokens received
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) internal returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Approve router to spend tokens
        IERC20(tokenA).forceApprove(ROUTER, amountADesired);
        IERC20(tokenB).forceApprove(ROUTER, amountBDesired);

        // Add liquidity
        (amountA, amountB, liquidity) = IPancakeV2Router(ROUTER).addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            to,
            block.timestamp + 300
        );

        return (amountA, amountB, liquidity);
    }

    /**
     * @dev Get reserves for a pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return reserveA Reserve of tokenA
     * @return reserveB Reserve of tokenB
     */
    function getReserves(address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        address pair = getPair(tokenA, tokenB);
        require(pair != address(0), "SwapV2Helper: Pair does not exist");

        (uint112 reserve0, uint112 reserve1,) = IPancakeV2Pair(pair).getReserves();
        (address token0,) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        (reserveA, reserveB) = tokenA == token0
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));

        return (reserveA, reserveB);
    }
}
