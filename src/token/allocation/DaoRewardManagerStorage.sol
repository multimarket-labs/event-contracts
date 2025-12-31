// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../interfaces/token/IDaoRewardManager.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


abstract contract DaoRewardManagerStorage is IDaoRewardManager {

    address public rewardTokenAddress;

    EnumerableSet.AddressSet internal authorizedCallers;

    uint256[100] private __gap;
}
