// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "../../interfaces/event/IFundingManager.sol";
import "../common/BaseManagerStorage.sol";

abstract contract FundingManagerStorage is BaseManagerStorage, IFundingManager {
    // Set of authorized callers who can trigger fund transfers to/from event contracts
    EnumerableSet.AddressSet internal authorizedCallers;

    uint256[100] private __gap;
}
