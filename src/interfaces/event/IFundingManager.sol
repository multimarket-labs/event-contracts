// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IFundingPod.sol";

interface IFundingManager {
    // Events
    event AuthorizedCallerAdded(address indexed caller);
    event AuthorizedCallerRemoved(address indexed caller);

    // Admin functions - manage support tokens
    function addSupportToken(address pod, address token) external;
    function removeSupportToken(address pod, address token) external;
    function setEventPod(address pod, address _eventPod) external;

    // Admin functions - manage authorized callers
    function addAuthorizedCaller(address caller) external;
    function removeAuthorizedCaller(address caller) external;

    // View functions
    function isAuthorizedCaller(address caller) external view returns (bool);
    function getAuthorizedCallers() external view returns (address[] memory);
}
