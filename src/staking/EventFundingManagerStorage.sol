// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/staking/IEventFundingManager.sol";


abstract contract EventFundingManagerStorage is IEventFundingManager {
    address public usdtTokenAddress;

    mapping(address => mapping(address => uint256)) public fundingBalanceForBetting;

    uint256[100] private __gap;
}
