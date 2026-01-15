// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {FundingPodStorage} from "./FundingPodStorage.sol";

contract FundingPod is Initializable, OwnableUpgradeable, PausableUpgradeable, FundingPodStorage {
    using SafeERC20 for IERC20;

    // Errors
    error OnlyFundingManager();
    error OnlyEventPod();
    error TokenNotSupported();
    error InvalidAmount();
    error InsufficientBalance();
    error InsufficientUserBalance();
    error InvalidAddress();
    error TransferFailed();

    // Modifiers
    modifier onlyFundingManager() {
        if (msg.sender != fundingManager) revert OnlyFundingManager();
        _;
    }

    modifier onlyEventPod() {
        if (msg.sender != eventPod) revert OnlyEventPod();
        _;
    }

    modifier onlySupportedToken(address token) {
        if (!EnumerableSet.contains(supportTokens, token)) revert TokenNotSupported();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _fundingManager, address _eventPod) external initializer {
        if (_owner == address(0) || _fundingManager == address(0) || _eventPod == address(0)) revert InvalidAddress();

        __Ownable_init(_owner);
        __Pausable_init();

        fundingManager = _fundingManager;
        eventPod = _eventPod;
    }

    /**
     * @notice User deposits tokens into the funding pod
     * @param token The token address to deposit (ETHAddress for native ETH)
     * @param amount The amount to deposit
     */
    function deposit(address token, uint256 amount) external payable whenNotPaused onlySupportedToken(token) {
        if (amount == 0) revert InvalidAmount();

        if (token == ETHAddress) {
            if (msg.value != amount) revert InvalidAmount();
        } else {
            if (msg.value != 0) revert InvalidAmount();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        userTokenBalances[msg.sender][token] += amount;
        tokenBalances[token] += amount;

        emit Deposit(msg.sender, token, amount);
    }

    /**
     * @notice User withdraws tokens from the funding pod
     * @param token The token address to withdraw
     * @param amount The amount to withdraw
     */
    function withdraw(address token, uint256 amount) external whenNotPaused onlySupportedToken(token) {
        if (amount == 0) revert InvalidAmount();
        if (userTokenBalances[msg.sender][token] < amount) revert InsufficientUserBalance();

        userTokenBalances[msg.sender][token] -= amount;
        tokenBalances[token] -= amount;

        if (token == ETHAddress) {
            (bool success,) = msg.sender.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit Withdraw(msg.sender, token, amount);
    }

    /**
     * @notice Get user's balance for a specific token
     * @param user The user address
     * @param token The token address
     * @return The user's balance
     */
    function getUserBalance(address user, address token) external view returns (uint256) {
        return userTokenBalances[user][token];
    }

    /**
     * @notice Transfer tokens to event contract for betting
     * @param token The token address to transfer
     * @param user The user address
     * @param amount The amount to transfer
     */
    function transferToEvent(address token, address user, uint256 amount)
        external
        onlyEventPod
        whenNotPaused
        onlySupportedToken(token)
    {
        if (amount == 0) revert InvalidAmount();
        if (tokenBalances[token] < amount) revert InsufficientBalance();
        if (userTokenBalances[user][token] < amount) revert InsufficientUserBalance();

        tokenBalances[token] -= amount;
        userTokenBalances[user][token] -= amount;

        if (token == ETHAddress) {
            (bool success,) = eventPod.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(eventPod, amount);
        }

        emit TransferToEvent(eventPod, token, user, amount);
    }

    /**
     * @notice Receive tokens from event contract (principal + rewards)
     * @param token The token address
     * @param user The user address
     * @param amount The principal amount returned
     * TODO How to reduce multiple function calls
     */
    function receiveFromEvent(address token, address user, uint256 amount)
        external
        payable
        onlyEventPod
        whenNotPaused
        onlySupportedToken(token)
    {
        require(tokenBalances[token] + amount >= getTokenBalance(token), "Invalid receive amount");
        tokenBalances[token] += amount;
        userTokenBalances[user][token] += amount;

        emit ReceiveFromEvent(eventPod, token, user, amount);
    }

    /**
     * @notice Add a supported token
     * @param token The token address to add
     */
    function addSupportToken(address token) external onlyFundingManager {
        if (token == address(0)) revert InvalidAddress();
        EnumerableSet.add(supportTokens, token);
    }

    /**
     * @notice Remove a supported token
     * @param token The token address to remove
     */
    function removeSupportToken(address token) external onlyFundingManager {
        EnumerableSet.remove(supportTokens, token);
    }

    /**
     * @notice Set the event pod address
     * @param _eventPod The new event pod address
     */
    function setEventPod(address _eventPod) external onlyFundingManager {
        if (_eventPod == address(0)) revert InvalidAddress();

        address oldEventPod = eventPod;
        eventPod = _eventPod;

        emit EventPodUpdated(oldEventPod, _eventPod);
    }

    /**
     * @notice Check if a token is supported
     * @param token The token address
     * @return Whether the token is supported
     */
    function isSupportToken(address token) external view returns (bool) {
        return EnumerableSet.contains(supportTokens, token);
    }

    /**
     * @notice Get all supported tokens
     * @return Array of supported token addresses
     */
    function getSupportTokens() external view returns (address[] memory) {
        return EnumerableSet.values(supportTokens);
    }

    /**
     * @notice Get the total balance for a token
     * @param token The token address
     * @return The total balance
     */
    function getTokenBalance(address token) public view returns (uint256) {
        return token == ETHAddress ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Required to receive ETH
    receive() external payable {}
}
