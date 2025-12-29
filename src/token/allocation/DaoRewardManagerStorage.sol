// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../interfaces/token/IDaoRewardManager.sol";


abstract contract DaoRewardManagerStorage is IDaoRewardManager {
    address public rewardTokenAddress;

    uint256[100] private __gap;
}
