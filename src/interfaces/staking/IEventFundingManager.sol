// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IEventFundingManager {
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
    function depositUsdt(uint256 amount) external returns (bool);
    function withdrawUsdt(address recipient, uint256 amount) external returns (bool);
}
