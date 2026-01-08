// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract BaseManagerStorage {
    EnumerableSet.AddressSet internal pods;
    
    uint256[97] private __gap;
}
