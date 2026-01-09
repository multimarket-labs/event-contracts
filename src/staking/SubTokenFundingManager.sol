// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/SwapHelper.sol";

import {SubTokenFundingManagerStorage} from "./SubTokenFundingManagerStorage.sol";

contract SubTokenFundingManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    SubTokenFundingManagerStorage
{
    using SafeERC20 for IERC20;

    constructor() {
        _disableInitializers();
    }

    modifier onlyOperatorManager() {
        require(msg.sender == address(operatorManager), "operatorManager");
        _;
    }

    /**
     * @dev Receive native tokens (BNB)
     */
    receive() external payable {}

    /**
     * @dev Initialize the Sub Token Funding Manager contract
     * @param initialOwner Initial owner address
     * @param _underlyingToken Underlying token address
     */
    function initialize(address initialOwner, address _underlyingToken) public initializer {
        __Ownable_init(initialOwner);
        underlyingToken = _underlyingToken;
    }

    /**
     * @dev Set trading pool address
     * @param _pool Pancake V3 trading pool address
     */
    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Invalid pool address");
        pool = _pool;
    }

    function setPoolType(uint8 _poolType) external onlyOwner {
        require(_poolType == 1 || _poolType == 2, "Invalid pool type");
        poolType = _poolType;
    }

    /**
     * @dev Set liquidity position NFT ID
     * @param _tokenId NFT Token ID of Pancake V3 liquidity position
     */
    function setPositionTokenId(uint256 _tokenId) external onlyOwner {
        require(_tokenId > 0, "Invalid token ID");
        positionTokenId = _tokenId;
    }

    /**
     * @dev Use funds to bet on event
     * @param amount add liquidity amount
     */
    function addLiquidity(uint256 amount) external onlyOperatorManager {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= IERC20(underlyingToken).balanceOf(address(this)), "Insufficient balance");

        if (poolType == 1) {
            (uint256 liquidityAdded, uint256 amount0Used, uint256 amount1Used) =
                SwapHelper.addLiquidityV2(V2_ROUTER, underlyingToken, USDT, amount, address(this));

            emit LiquidityAdded(1, 0, liquidityAdded, amount0Used, amount1Used);
        } else {
            (uint256 liquidityAdded, uint256 amount0Used, uint256 amount1Used) = SwapHelper.addLiquidityV3(
                POSITION_MANAGER, pool, positionTokenId, underlyingToken, USDT, amount, SLIPPAGE_TOLERANCE
            );

            emit LiquidityAdded(2, positionTokenId, liquidityAdded, amount0Used, amount1Used);
        }
    }
}
