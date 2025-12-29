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

    receive() external payable {}

    function initialize(address initialOwner, address _rewardTokenAddress) public initializer  {
        __Ownable_init(initialOwner);
        rewardTokenAddress = _rewardTokenAddress;
    }

    function withdraw(address recipient, uint256 amount) external {
        require(amount <= _tokenBalance(), "DaoRewardManager: withdraw amount more token balance in this contracts");

        IERC20(rewardTokenAddress).safeTransferFrom(address(this), amount, amount);
    }


    // ========= internal =========
    function _tokenBalance() internal view virtual returns (uint256) {
        return IERC20(rewardTokenAddress).balanceOf(address(this));
    }
}
