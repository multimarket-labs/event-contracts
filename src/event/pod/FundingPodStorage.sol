// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../interfaces/event/IFundingPod.sol";

abstract contract FundingPodStorage is IFundingPod {
    address public constant ETHAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address public fundingManager;
    address[] public SupportTokens;

    mapping(address => bool) public IsSupportToken;
    mapping(address => uint256) public tokenBalances;
    mapping(address => mapping(address => uint256)) public userTokenBalances;

    uint256[100] private __gap;
}
