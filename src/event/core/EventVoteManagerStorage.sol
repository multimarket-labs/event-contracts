// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../interfaces/event/IEventVoteManager.sol";

abstract contract EventVoteManagerStorage is IEventVoteManager {
    // Event Manager address
    address public eventManager;
    
    // Caller address that can create and complete votes
    address public caller;
    
    uint256[94] private __gap;
}
