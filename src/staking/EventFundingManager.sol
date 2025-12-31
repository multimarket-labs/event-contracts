// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { EventFundingManagerStorage } from "./EventFundingManagerStorage.sol";

contract EventFundingManager is Initializable, OwnableUpgradeable, PausableUpgradeable, EventFundingManagerStorage {
    using SafeERC20 for IERC20;

    constructor(){
        _disableInitializers();
    }

    /**
     * @dev 接收原生代币（BNB）
     */
    receive() external payable {}

    /**
     * @dev 初始化事件资金管理器合约
     * @param initialOwner 初始所有者地址
     * @param _usdtTokenAddress USDT 代币地址
     */
    function initialize(address initialOwner, address _usdtTokenAddress) public initializer  {
        __Ownable_init(initialOwner);
        usdtTokenAddress = _usdtTokenAddress;
    }

    /**
     * @dev 存入 USDT 到事件资金池
     * @param amount 要存入的 USDT 金额
     * @return 是否成功
     */
    function depositUsdt(uint256 amount) external whenNotPaused returns (bool) {
        IERC20(usdtTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        fundingBalanceForBetting[msg.sender][usdtTokenAddress] += amount;
        emit DepositUsdt(
            usdtTokenAddress,
            msg.sender,
            amount
        );
        return true;
    }

    /**
     * @dev 使用资金投注事件
     * @param event_pool 事件池地址
     * @param amount 投注金额
     */
    function bettingEvent(address event_pool, uint256 amount) external {
        require(fundingBalanceForBetting[msg.sender][usdtTokenAddress] >= 0, "amount is zero");
        // todo betting event
    }
}
