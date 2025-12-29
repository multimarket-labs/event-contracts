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

    receive() external payable {
        FundingBalance[NativeTokenAddress] += msg.value;
        emit Deposit(
            NativeTokenAddress,
            msg.sender,
            msg.value
        );
    }

    function initialize(address initialOwner, address _rewardTokenAddress, address _underlyingToken) public initializer  {
        __Ownable_init(initialOwner);
        rewardTokenAddress = _rewardTokenAddress;
        underlyingToken = _underlyingToken;
    }

    function deposit() external payable whenNotPaused returns (bool) {
        FundingBalance[NativeTokenAddress] += msg.value;
        emit Deposit(
            NativeTokenAddress,
            msg.sender,
            msg.value
        );
        return true;
    }

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

    function withdrawErc20(address recipient, uint256 amount) external whenNotPaused returns (bool){
        require(amount <= _tokenBalance(), "FomoTreasureManager: withdraw erc20 amount more token balance in this contracts");

        FundingBalance[underlyingToken] -= amount;

        IERC20(rewardTokenAddress).safeTransferFrom(address(this), recipient, amount);

        emit Withdraw(
            underlyingToken,
            msg.sender,
            recipient,
            amount
        );
        return true;
    }

    // ========= internal =========
    function _tokenBalance() internal view virtual returns (uint256) {
        return IERC20(rewardTokenAddress).balanceOf(address(this));
    }
}
