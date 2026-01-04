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
     * @dev Receive native tokens (BNB) and record to funding balance
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
     * @dev Initialize the FOMO Treasure Manager contract
     * @param initialOwner Initial owner address
     * @param _underlyingToken Underlying token address (USDT)
     */
    function initialize(address initialOwner,address _underlyingToken) public initializer  {
        __Ownable_init(initialOwner);
        underlyingToken = _underlyingToken;
    }

    /**
     * @dev Pause the contract (only owner can call)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract (only owner can call)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Deposit native tokens (BNB) to FOMO Treasury
     * @return Whether the operation was successful
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
     * @dev Deposit ERC20 tokens (USDT) to FOMO Treasury
     * @param amount Amount of tokens to deposit
     * @return Whether the operation was successful
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
     * @dev Withdraw native tokens (BNB)
     * @param withdrawAddress Receiving address
     * @param amount Withdrawal amount
     * @return Whether the operation was successful
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
     * @dev Withdraw ERC20 tokens (USDT)
     * @param recipient Recipient address
     * @param amount Withdrawal amount
     * @return Whether the operation was successful
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
     * @dev Get the ERC20 token balance in the contract
     * @return Token balance in the contract
     */
    function _tokenBalance() internal view virtual returns (uint256) {
        return IERC20(underlyingToken).balanceOf(address(this));
    }
}
