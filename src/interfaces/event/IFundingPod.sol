// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IFundingPod {
    // Events
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event TransferToEvent(address indexed eventPod, address indexed token, address indexed user, uint256 amount);
    event ReceiveFromEvent(address indexed eventPod, address indexed token, address indexed user, uint256 amount);
    event EventPodUpdated(address indexed oldEventPod, address indexed newEventPod);

    // User functions
    function deposit(address token, uint256 amount) external payable;
    function withdraw(address token, uint256 amount) external;
    function getUserBalance(address user, address token) external view returns (uint256);

    // EventPod functions (called by EventPod)
    function transferToEvent(address token, address user, uint256 amount) external;
    function receiveFromEvent(address token, address user, uint256 amount) external payable;

    // Admin functions (called by FundingManager)
    function addSupportToken(address token) external;
    function removeSupportToken(address token) external;
    function setEventPod(address _eventPod) external;

    // View functions
    function isSupportToken(address token) external view returns (bool);
    function getSupportTokens() external view returns (address[] memory);
    function getTokenBalance(address token) external view returns (uint256);

    // Pausable functions
    function pause() external;
    function unpause() external;
}
