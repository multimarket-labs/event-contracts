// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../common/BaseManager.sol";
import "./FundingManagerStorage.sol";
import "../pod/FundingPod.sol";

contract FundingManager is BaseManager, FundingManagerStorage {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Errors
    error InvalidPod();
    error InvalidAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        if (_owner == address(0)) revert InvalidAddress();

        __Ownable_init(_owner);
    }

    /**
     * @notice Add a supported token to a funding pod
     * @param pod The funding pod address
     * @param token The token address to add
     */
    function addSupportToken(address pod, address token) external onlyOwner onlyPod(pod) {
        FundingPod(payable(pod)).addSupportToken(token);
    }

    /**
     * @notice Remove a supported token from a funding pod
     * @param pod The funding pod address
     * @param token The token address to remove
     */
    function removeSupportToken(address pod, address token) external onlyOwner onlyPod(pod) {
        FundingPod(payable(pod)).removeSupportToken(token);
    }

    /**
     * @notice Set the event pod address for a funding pod
     * @param pod The funding pod address
     * @param _eventPod The event pod address
     */
    function setEventPod(address pod, address _eventPod) external onlyOwner onlyPod(pod) {
        FundingPod(payable(pod)).setEventPod(_eventPod);
    }

    /**
     * @notice Add an authorized caller
     * @param caller The caller address to authorize
     */
    function addAuthorizedCaller(address caller) external onlyOwner {
        if (caller == address(0)) revert InvalidAddress();

        if (!authorizedCallers.contains(caller)) {
            authorizedCallers.add(caller);
            emit AuthorizedCallerAdded(caller);
        }
    }

    /**
     * @notice Remove an authorized caller
     * @param caller The caller address to remove
     */
    function removeAuthorizedCaller(address caller) external onlyOwner {
        if (authorizedCallers.contains(caller)) {
            authorizedCallers.remove(caller);
            emit AuthorizedCallerRemoved(caller);
        }
    }

    /**
     * @notice Check if an address is an authorized caller
     * @param caller The address to check
     * @return Whether the address is authorized
     */
    function isAuthorizedCaller(address caller) external view returns (bool) {
        return authorizedCallers.contains(caller);
    }

    /**
     * @notice Get all authorized callers
     * @return Array of authorized caller addresses
     */
    function getAuthorizedCallers() external view returns (address[] memory) {
        return authorizedCallers.values();
    }

    // Required to receive ETH
    receive() external payable {}
}
