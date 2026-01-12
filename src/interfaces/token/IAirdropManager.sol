// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IAirdropManager {
    event Withdraw(address indexed tokenAddress, address indexed recipient, uint256 amount);
    function withdraw(address recipient, uint256 amount) external;
}
