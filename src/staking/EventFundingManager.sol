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

    receive() external payable {}

    function initialize(address initialOwner, address _usdtTokenAddress) public initializer  {
        __Ownable_init(initialOwner);
        usdtTokenAddress = _usdtTokenAddress;
    }

    function depositUsdt(uint256 amount) external whenNotPaused returns (bool) {
        IERC20(usdtTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        FundingBalance[usdtTokenAddress] += amount;
        emit Deposit(
            usdtTokenAddress,
            msg.sender,
            amount
        );
        return true;
    }

    function withdrawUsdt(address recipient, uint256 amount) external whenNotPaused returns (bool){
        require(amount <= _tokenBalance(), "FomoTreasureManager: withdraw erc20 amount more token balance in this contracts");

        FundingBalance[usdtTokenAddress] -= amount;

        IERC20(usdtTokenAddress).safeTransferFrom(address(this), recipient, amount);

        emit Withdraw(
            usdtTokenAddress,
            msg.sender,
            recipient,
            amount
        );
        return true;
    }

    // ========= internal =========
    function _tokenBalance() internal view virtual returns (uint256) {
        return IERC20(usdtTokenAddress).balanceOf(address(this));
    }
}
