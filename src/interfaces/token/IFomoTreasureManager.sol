// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IFomoTreasureManager {
    event Deposit(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount
    );

    event Withdraw(
        address indexed tokenAddress,
        address sender,
        address withdrawAddress,
        uint256 amount
    );
    function deposit() external payable returns (bool);
    function depositErc20(uint256 amount) external returns (bool);
    function withdraw(address payable withdrawAddress, uint256 amount) external payable returns (bool);
    function withdrawErc20(address recipient, uint256 amount) external returns (bool);
}
