// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { EventFundingManagerStorage } from "./EventFundingManagerStorage.sol";

contract EventFundingManager is Initializable, OwnableUpgradeable, PausableUpgradeable, EventFundingManagerStorage {
    using SafeERC20 for IERC20;

    constructor(){
        _disableInitializers();
    }

    /**
     * @dev Receive native tokens (BNB)
     */
    receive() external payable {}

    /**
     * @dev Initialize the Event Funding Manager contract
     * @param initialOwner Initial owner address
     * @param _usdtTokenAddress USDT token address
     */
    function initialize(address initialOwner, address _usdtTokenAddress) public initializer  {
        __Ownable_init(initialOwner);
        usdtTokenAddress = _usdtTokenAddress;
    }

    /**
     * @dev Deposit USDT to the event funding pool
     * @param amount Amount of USDT to deposit
     * @return Whether the operation was successful
     */
    function depositUsdt(uint256 amount) external whenNotPaused returns (bool) {
        IERC20(usdtTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        fundingBalanceForBetting[msg.sender][usdtTokenAddress] += amount;
        emit DepositUsdt(
            usdtTokenAddress,
            msg.sender,
            amount
        );
        return true;
    }

    /**
     * @dev Use funds to bet on event
     * @param event_pool Event pool address
     * @param amount Betting amount
     */
    function bettingEvent(address event_pool, uint256 amount) external {
        require(fundingBalanceForBetting[msg.sender][usdtTokenAddress] >= 0, "amount is zero");
        // todo betting event
    }
}
