// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IEventFundingManager {
    event DepositUsdt(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount
    );

    function depositUsdt(uint256 amount) external returns (bool);
    function bettingEvent(address event_pool, uint256 amount) external;
}
