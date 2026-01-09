// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ISubTokenFundingManager {
    // Events
    event LiquidityAdded(
        uint8 indexed poolType, uint256 indexed tokenId, uint256 liquidity, uint256 amount0, uint256 amount1
    );

    // View Functions
    function POSITION_MANAGER() external view returns (address);
    function SLIPPAGE_TOLERANCE() external view returns (uint256);
    function pool() external view returns (address);
    function positionTokenId() external view returns (uint256);
    function V2_ROUTER() external view returns (address);
    function poolType() external view returns (uint8);
    function underlyingToken() external view returns (address);
    function USDT() external view returns (address);
    function operatorManager() external view returns (address);

    // External Functions
    function initialize(address initialOwner, address _underlyingToken) external;
    function setPool(address _pool) external;
    function setPoolType(uint8 _poolType) external;
    function setPositionTokenId(uint256 _tokenId) external;
    function addLiquidity(uint256 amount) external;
}
