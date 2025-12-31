// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { DaoRewardManagerStorage } from "./DaoRewardManagerStorage.sol";

contract DaoRewardManager is Initializable, OwnableUpgradeable, PausableUpgradeable, DaoRewardManagerStorage {
    using SafeERC20 for IERC20;

    constructor(){
        _disableInitializers();
    }

    /**
     * @dev 接收原生代币（BNB）
     */
    receive() external payable {}

    /**
     * @dev 初始化 DAO 奖励管理器合约
     * @param initialOwner 初始所有者地址
     * @param _rewardTokenAddress 奖励代币地址（CMT）
     */
    function initialize(address initialOwner, address _rewardTokenAddress) public initializer  {
        __Ownable_init(initialOwner);
        rewardTokenAddress = _rewardTokenAddress;
    }

    /**
     * @dev 从奖励池中提取代币
     * @param recipient 接收人地址
     * @param amount 提取金额
     */
    function withdraw(address recipient, uint256 amount) external {
        require(amount <= _tokenBalance(), "DaoRewardManager: withdraw amount more token balance in this contracts");

        IERC20(rewardTokenAddress).safeTransfer(recipient, amount);
    }


    // ========= internal =========
    /**
     * @dev 获取合约中的代币余额
     * @return 合约中的代币余额
     */
    function _tokenBalance() internal view virtual returns (uint256) {
        return IERC20(rewardTokenAddress).balanceOf(address(this));
    }
}
