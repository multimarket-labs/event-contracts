// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/staking/pancake/IPancakeV3Pool.sol";

library SwapV3Helper {
    using SafeERC20 for IERC20;

    function swapTokenToUsdt(
        address pool,
        address tokenIn,
        address usdt,
        uint256 amountIn,
        address recipient
    ) internal returns (uint256) {
        require(pool != address(0), "Pool not set");
        require(amountIn > 0, "Amount must be greater than 0");

        IPancakeV3Pool v3Pool = IPancakeV3Pool(pool);
        (uint160 sqrtPriceX96,,,,,,) = v3Pool.slot0();

        bool zeroForOne = tokenIn < usdt;
        uint160 sqrtPriceLimitX96;
        if (zeroForOne) {
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 95) / 100);
        } else {
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 105) / 100);
        }

        uint256 usdtBefore = IERC20(usdt).balanceOf(recipient);

        IPancakeV3Pool(pool).swap(
            recipient,
            zeroForOne,
            int256(amountIn),
            sqrtPriceLimitX96,
            abi.encode(pool)
        );

        uint256 usdtAfter = IERC20(usdt).balanceOf(recipient);
        uint256 usdtReceived = usdtAfter - usdtBefore;

        return usdtReceived;
    }

    function swapUsdtToToken(
        address pool,
        address usdt,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) internal returns (uint256) {
        require(pool != address(0), "Pool not set");
        require(amountIn > 0, "Amount must be greater than 0");

        IPancakeV3Pool v3Pool = IPancakeV3Pool(pool);
        (uint160 sqrtPriceX96,,,,,,) = v3Pool.slot0();

        bool zeroForOne = usdt < tokenOut;
        uint160 sqrtPriceLimitX96;
        if (zeroForOne) {
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 95) / 100);
        } else {
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 105) / 100);
        }

        uint256 tokenBefore = IERC20(tokenOut).balanceOf(recipient);

        IPancakeV3Pool(pool).swap(
            recipient,
            zeroForOne,
            int256(amountIn),
            sqrtPriceLimitX96,
            abi.encode(pool)
        );

        uint256 tokenAfter = IERC20(tokenOut).balanceOf(recipient);
        uint256 tokenReceived = tokenAfter - tokenBefore;

        return tokenReceived;
    }

    function handleSwapCallback(
        address pool,
        int256 amount0Delta,
        int256 amount1Delta,
        address recipient
    ) internal {
        if (amount0Delta > 0) {
            address token0 = IPancakeV3Pool(pool).token0();
            IERC20(token0).safeTransfer(recipient, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            address token1 = IPancakeV3Pool(pool).token1();
            IERC20(token1).safeTransfer(recipient, uint256(amount1Delta));
        }
    }
}
