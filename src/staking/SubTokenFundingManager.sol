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
     * @param _usdt USDT token address
     */
    function initialize(address initialOwner, address _usdt) public initializer {
        __Ownable_init(initialOwner);
        USDT = _usdt;
    }

    function setSubToken(address _subToken) external onlyOwner {
        subToken = _subToken;
    }

    /**
     * @dev Add liquidity to trading pool
     * @param amount Amount of underlying token to add to liquidity pool
     */
    function addLiquidity(uint256 amount) external onlyOperatorManager {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= IERC20(USDT).balanceOf(address(this)), "Insufficient balance");

        (uint256 liquidityAdded, uint256 amount0Used, uint256 amount1Used) =
            SwapHelper.addLiquidityV2(V2_ROUTER, USDT, subToken, amount, address(this));

        emit LiquidityAdded(liquidityAdded, amount0Used, amount1Used);
    }
}
