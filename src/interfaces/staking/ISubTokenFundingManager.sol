// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ISubTokenFundingManager {
    // Events
    event LiquidityAdded(uint256 liquidity, uint256 amount0, uint256 amount1);

    // View Functions
    function V2_ROUTER() external view returns (address);
    function USDT() external view returns (address);
    function operatorManager() external view returns (address);

    // External Functions
    function addLiquidity(uint256 amount) external;
}
