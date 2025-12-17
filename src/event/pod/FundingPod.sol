// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


import { FundingPodStorage } from "./FundingPodStorage.sol";


contract FundingPod is Initializable, OwnableUpgradeable, PausableUpgradeable, FundingPodStorage {
    using SafeERC20 for IERC20;

    modifier onlyFundingManager() {
        require(msg.sender == address(fundingManager), "onlyFundingManager");
        _;
    }

    constructor(){
        _disableInitializers();
    }

    receive() external payable {}

    function initialize(address initialOwner, address _fundingManager) public initializer  {
        __Ownable_init(initialOwner);
        fundingManager = _fundingManager;
    }


    function deposit(address tokenAddress, uint256 amount) external onlyFundingManager {
        if (!IsSupportToken[tokenAddress]) {
            revert TokenIsNotSupported(tokenAddress);
        }

        userTokenBalances[msg.sender][tokenAddress] += amount;
        tokenBalances[tokenAddress] += amount;

        emit DepositToken(
            tokenAddress,
            msg.sender,
            amount
        );
    }


    function withdraw(address payable withdrawAddress, uint256 amount) external onlyFundingManager {

    }


    function setSupportERC20Token(address ERC20Address, bool isValid) external onlyOwner {
        IsSupportToken[ERC20Address] = isValid;
        if (isValid) {
            SupportTokens.push(ERC20Address);
        }
        emit SetSupportTokenEvent(ERC20Address, isValid, block.chainid);
    }

}
