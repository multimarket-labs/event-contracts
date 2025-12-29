// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IDaoRewardManager {
    function withdraw(address recipient, uint256 amount) external;
}
