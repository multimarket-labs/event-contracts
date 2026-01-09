// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/staking/pancake/IPancakeV3Pool.sol";
import "../interfaces/staking/pancake/IPancakeV2Router.sol";
import "../interfaces/staking/pancake/IV3NonfungiblePositionManager.sol";
import "@pancake-v2-periphery/interfaces/IPancakeRouter02.sol";

library SwapHelper {
    using SafeERC20 for IERC20;

    /**
     * @dev Swap tokens on PancakeSwap V3 pool
     * @param pool PancakeSwap V3 pool address
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input token to swap
     * @param recipient Address to receive output tokens
     * @return Amount of output tokens received
     */
    function swapV3(address pool, address tokenIn, address tokenOut, uint256 amountIn, address recipient)
        internal
        returns (uint256)
    {
        IPancakeV3Pool v3Pool = IPancakeV3Pool(pool);
        (uint160 sqrtPriceX96,,,,,,) = v3Pool.slot0();

        bool zeroForOne = tokenIn < tokenOut;
        uint160 sqrtPriceLimitX96;
        if (zeroForOne) {
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 95) / 100);
        } else {
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 105) / 100);
        }

        uint256 tokenOutBefore = IERC20(tokenOut).balanceOf(recipient);
        IPancakeV3Pool(pool).swap(recipient, zeroForOne, int256(amountIn), sqrtPriceLimitX96, abi.encode(pool));

        uint256 tokenOutAfter = IERC20(tokenOut).balanceOf(recipient);
        uint256 tokenOutReceived = tokenOutAfter - tokenOutBefore;

        return tokenOutReceived;
    }

    /**
     * @dev Handle PancakeSwap V3 swap callback by transferring tokens to pool
     * @param pool PancakeSwap V3 pool address
     * @param amount0Delta Change in token0 balance (positive means tokens owed to pool)
     * @param amount1Delta Change in token1 balance (positive means tokens owed to pool)
     * @param recipient Recipient address for the callback
     */
    function handleSwapCallback(address pool, int256 amount0Delta, int256 amount1Delta, address recipient) internal {
        if (amount0Delta > 0) {
            address token0 = IPancakeV3Pool(pool).token0();
            IERC20(token0).safeTransfer(recipient, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            address token1 = IPancakeV3Pool(pool).token1();
            IERC20(token1).safeTransfer(recipient, uint256(amount1Delta));
        }
    }

    /**
     * @dev Add liquidity to PancakeSwap V3 position
     * @param positionManager NFT Position Manager contract address
     * @param pool PancakeSwap V3 pool address
     * @param positionTokenId NFT token ID of the liquidity position
     * @param token0 First token address
     * @param token1 Second token address
     * @param amount Total amount of token0 to use (50% will be swapped to token1)
     * @param slippageTolerance Slippage tolerance percentage (e.g., 95 for 5% slippage)
     * @return liquidityAdded Amount of liquidity tokens minted
     * @return amount0Used Amount of token0 used
     * @return amount1Used Amount of token1 used
     */
    function addLiquidityV3(
        address positionManager,
        address pool,
        uint256 positionTokenId,
        address token0,
        address token1,
        uint256 amount,
        uint256 slippageTolerance
    ) internal returns (uint256 liquidityAdded, uint256 amount0Used, uint256 amount1Used) {
        uint256 swapAmount = amount / 2;
        uint256 remainingAmount = amount - swapAmount;

        IERC20(token0).approve(positionManager, amount);
        uint256 underlyingTokenReceived = SwapHelper.swapV3(pool, token0, token1, swapAmount, address(this));

        uint256 underlyingTokenBalance = underlyingTokenReceived;
        uint256 usdtBalance = remainingAmount;

        IERC20(token1).approve(positionManager, underlyingTokenBalance);

        bool zeroForOne = token0 < token1;
        uint256 amount0Desired;
        uint256 amount1Desired;
        if (zeroForOne) {
            amount0Desired = usdtBalance;
            amount1Desired = underlyingTokenBalance;
        } else {
            amount0Desired = underlyingTokenBalance;
            amount1Desired = usdtBalance;
        }

        IV3NonfungiblePositionManager.IncreaseLiquidityParams memory params =
            IV3NonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: (amount0Desired * slippageTolerance) / 100,
                amount1Min: (amount1Desired * slippageTolerance) / 100,
                deadline: block.timestamp + 15 minutes
            });
        (liquidityAdded, amount0Used, amount1Used) =
            IV3NonfungiblePositionManager(positionManager).increaseLiquidity(params);
    }

    /**
     * @dev Swap tokens on PancakeSwap V2 router
     * @param router PancakeSwap V2 router address
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amount Amount of input token to swap
     * @param to Address to receive output tokens
     * @return Amount of output tokens received
     */
    function swapV2(address router, address tokenIn, address tokenOut, uint256 amount, address to) internal returns (uint256) {
        uint256 balOld = IERC20(tokenOut).balanceOf(to);
        IERC20(tokenIn).approve(router, amount);
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        IPancakeRouter02(router)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(amount, 1, path, to, block.timestamp + 20);
        uint256 balNew = IERC20(tokenOut).balanceOf(to);
        return balNew - balOld;
    }

    /**
     * @dev Add liquidity to PancakeSwap V2 pool
     * @param router PancakeSwap V2 router address
     * @param token0 First token address
     * @param token1 Second token address
     * @param amount Total amount of token0 to use (50% will be swapped to token1)
     * @param to Address to receive LP tokens
     * @return liquidityAdded Amount of LP tokens minted
     * @return amount0Used Amount of token0 used
     * @return amount1Used Amount of token1 used
     */
    function addLiquidityV2(
        address router,
        address token0,
        address token1,
        uint256 amount,
        address to
    ) internal returns (uint256 liquidityAdded, uint256 amount0Used, uint256 amount1Used) {
        uint token0Amount = amount / 2;
        uint token1Amount = SwapHelper.swapV2(router, token0, token1, token0Amount, address(this));
        IERC20(token0).approve(router, token0Amount);
        IERC20(token1).approve(router, token1Amount);
        (amount0Used,amount1Used, liquidityAdded) =
            IPancakeRouter02(router).addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, to, block.timestamp);
    }
}
