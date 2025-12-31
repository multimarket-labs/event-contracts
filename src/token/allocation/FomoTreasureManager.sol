// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FomoTreasureManagerStorage } from "./FomoTreasureManagerStorage.sol";

contract FomoTreasureManager is Initializable, OwnableUpgradeable, PausableUpgradeable, FomoTreasureManagerStorage {
    using SafeERC20 for IERC20;

    constructor(){
        _disableInitializers();
    }

    /**
     * @dev 接收原生代币（BNB）并记录到资金余额
     */
    receive() external payable {
        FundingBalance[NativeTokenAddress] += msg.value;
        emit Deposit(
            NativeTokenAddress,
            msg.sender,
            msg.value
        );
    }

    /**
     * @dev 初始化 FOMO 财库管理器合约
     * @param initialOwner 初始所有者地址
     * @param _underlyingToken 底层代币地址（USDT）
     */
    function initialize(address initialOwner,address _underlyingToken) public initializer  {
        __Ownable_init(initialOwner);
        underlyingToken = _underlyingToken;
    }

    /**
     * @dev 暂停合约（仅所有者可调用）
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 恢复合约（仅所有者可调用）
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 存入原生代币（BNB）到 FOMO 财库
     * @return 是否成功
     */
    function deposit() external payable whenNotPaused returns (bool) {
        FundingBalance[NativeTokenAddress] += msg.value;
        emit Deposit(
            NativeTokenAddress,
            msg.sender,
            msg.value
        );
        return true;
    }

    /**
     * @dev 存入 ERC20 代币（USDT）到 FOMO 财库
     * @param amount 要存入的代币数量
     * @return 是否成功
     */
    function depositErc20(uint256 amount) external whenNotPaused returns (bool) {
        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);
        FundingBalance[underlyingToken] += amount;
        emit Deposit(
            underlyingToken,
            msg.sender,
            amount
        );
        return true;
    }

    /**
     * @dev 提取原生代币（BNB）
     * @param withdrawAddress 接收地址
     * @param amount 提取金额
     * @return 是否成功
     */
    function withdraw(address payable withdrawAddress, uint256 amount) external payable whenNotPaused returns (bool) {
        require(address(this).balance >= amount, "FomoTreasureManager withdraw: insufficient native token balance in contract");
        FundingBalance[NativeTokenAddress] -= amount;
        (bool success, ) = withdrawAddress.call{value: amount}("");
        if (!success) {
            return false;
        }
        emit Withdraw(
            NativeTokenAddress,
            msg.sender,
            withdrawAddress,
            amount
        );
        return true;
    }

    /**
     * @dev 提取 ERC20 代币（USDT）
     * @param recipient 接收人地址
     * @param amount 提取金额
     * @return 是否成功
     */
    function withdrawErc20(address recipient, uint256 amount) external whenNotPaused returns (bool){
        require(amount <= _tokenBalance(), "FomoTreasureManager: withdraw erc20 amount more token balance in this contracts");
        FundingBalance[underlyingToken] -= amount;

        IERC20(underlyingToken).safeTransfer(recipient, amount);

        emit Withdraw(
            underlyingToken,
            msg.sender,
            recipient,
            amount
        );
        return true;
    }

    // ========= internal =========
    /**
     * @dev 获取合约中的 ERC20 代币余额
     * @return 合约中的代币余额
     */
    function _tokenBalance() internal view virtual returns (uint256) {
        return IERC20(underlyingToken).balanceOf(address(this));
    }
}
