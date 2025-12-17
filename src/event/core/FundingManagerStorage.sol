// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../interfaces/event/IFundingManager.sol";

abstract contract FundingManagerStorage is IFundingManager {
    address public fundingPodWhitelister;

    mapping(IFundingPod => bool) public podIsWhitelistedForDeposit;
}
