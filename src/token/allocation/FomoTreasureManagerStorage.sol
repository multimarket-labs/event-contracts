// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../interfaces/token/IFomoTreasureManager.sol";

abstract contract  FomoTreasureManagerStorage is IFomoTreasureManager {
    address public constant NativeTokenAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address public underlyingToken;

    mapping(address => uint256) public FundingBalance;


    uint256[100] private __gap;
}
