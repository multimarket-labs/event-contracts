// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { DaoRewardManagerStorage } from "./DaoRewardManagerStorage.sol";

contract DaoRewardManager is Initializable, OwnableUpgradeable, PausableUpgradeable, DaoRewardManagerStorage {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(){
        _disableInitializers();
    }

    modifier onAuthorizedCaller() {
        require(authorizedCallers.contains(msg.sender), "DaoRewardManager: caller is not authorized");
        _;
    }

    /**
     * @dev Receive native tokens (BNB)
     */
    receive() external payable {}

    /**
     * @dev Initialize the DAO Reward Manager contract
     * @param initialOwner Initial owner address
     * @param _rewardTokenAddress Reward token address (CMT)
     */
    function initialize(address initialOwner, address _rewardTokenAddress, address _nodeManager, address _stakingManager) public initializer  {
        __Ownable_init(initialOwner);
        rewardTokenAddress = _rewardTokenAddress;
        authorizedCallers.add(_nodeManager);
        authorizedCallers.add(_stakingManager);
    }

    /**
     * @dev Withdraw tokens from the reward pool
     * @param recipient Recipient address
     * @param amount Withdrawal amount
     */
    function withdraw(address recipient, uint256 amount) external onAuthorizedCaller {
        require(amount <= _tokenBalance(), "DaoRewardManager: withdraw amount more token balance in this contracts");

        IERC20(rewardTokenAddress).safeTransfer(recipient, amount);
    }


    // ========= internal =========
    /**
     * @dev Get the token balance in the contract
     * @return Token balance in the contract
     */
    function _tokenBalance() internal view virtual returns (uint256) {
        return IERC20(rewardTokenAddress).balanceOf(address(this));
    }
}
