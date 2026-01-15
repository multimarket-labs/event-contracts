// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {MarketManagerStorage} from "./MarketManagerStorage.sol";

contract MarketManager is Initializable, OwnableUpgradeable, PausableUpgradeable, MarketManagerStorage {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor() {
        _disableInitializers();
    }

    modifier onAuthorizedCaller() {
        require(authorizedCallers.contains(msg.sender), "MarketManager: caller is not authorized");
        _;
    }

    /**
     * @dev Initialize the DAO Reward Manager contract
     * @param initialOwner Initial owner address
     * @param _token Reward token address (CMT)
     */
    function initialize(address initialOwner, address _token) public initializer {
        __Ownable_init(initialOwner);
        token = _token;
    }

    /**
     * @dev Add an authorized caller
     * @param caller Address to be authorized
     */
    function addAuthorizedCaller(address caller) external onlyOwner {
        authorizedCallers.add(caller);
    }

    /**
     * @dev Withdraw tokens from the reward pool
     * @param recipient Recipient address
     * @param amount Withdrawal amount
     */
    function withdraw(address recipient, uint256 amount) external onAuthorizedCaller {
        require(amount <= _tokenBalance(), "AirdropManager: withdraw amount more token balance in this contracts");

        IERC20(token).safeTransfer(recipient, amount);

        emit Withdraw(token, recipient, amount);
    }

    // ========= internal =========
    /**
     * @dev Get the token balance in the contract
     * @return Token balance in the contract
     */
    function _tokenBalance() internal view virtual returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
