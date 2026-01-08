// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/staking/pancake/IPancakeV2Router.sol";
import "../interfaces/staking/pancake/IPancakeV2Pair.sol";

library SwapHelper {
    using SafeERC20 for IERC20;

    // PancakeSwap V2 Router address on BSC
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    /**
     * @dev Swap token to USDT using PancakeSwap V2
     * @param tokenIn Input token address
     * @param usdt USDT token address
     * @param amountIn Amount of input token
     * @param recipient Recipient address
     * @return Amount of USDT received
     */
    function swapTokenToUsdt(
        address, // pool parameter not used in V2
        address tokenIn,
        address usdt,
        uint256 amountIn,
        address recipient
    ) internal returns (uint256) {
        require(amountIn > 0, "Amount must be greater than 0");

        // Approve router to spend tokens
        IERC20(tokenIn).forceApprove(ROUTER, amountIn);

        // Create swap path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = usdt;

        // Get expected output amount
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
     */
    function swapUsdtToToken(
        address, // pool parameter not used in V2
        address usdt,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) internal returns (uint256) {
        require(amountIn > 0, "Amount must be greater than 0");

        // Approve router to spend USDT
        IERC20(usdt).forceApprove(ROUTER, amountIn);

        // Create swap path
        address[] memory path = new address[](2);
        path[0] = usdt;
        path[1] = tokenOut;

        // Get expected output amount
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
     * @dev This function is no longer needed for V2
     * V2 doesn't use callbacks like V3
     * Kept for backward compatibility but does nothing
     */
    function handleSwapCallback(
        address,
        int256,
        int256,
        address
    ) internal pure {
        // V2 doesn't use callbacks, this function is a no-op
        revert("V2 does not use callbacks");
    }
}
