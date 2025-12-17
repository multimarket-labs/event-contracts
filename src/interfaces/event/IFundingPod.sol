// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IFundingPod {
    event DepositToken(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount
    );

    event WithdrawToken(
        address indexed tokenAddress,
        address sender,
        address withdrawAddress,
        uint256 amount
    );

    event SetSupportTokenEvent(address indexed token, bool isSupport, uint256 chainId);

    error LessThanZero(uint256 amount);
    error TokenIsNotSupported(address ERC20Address);

    function deposit(address tokenAddress, uint256 amount) external;
    function withdraw(address payable withdrawAddress, uint256 amount) external;

    function setSupportERC20Token(address ERC20Address, bool isValid) external;
}
