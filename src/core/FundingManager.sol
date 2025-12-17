// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./FundingManagerStorage.sol";

contract FundingManager is Initializable, OwnableUpgradeable, PausableUpgradeable, FundingManagerStorage  {
    using SafeERC20 for IERC20;

    modifier onlyFundingPodWhitelister() {
        require(
            msg.sender == fundingPodWhitelister,
            "StrategyManager.onlyStrategyWhitelister: not the strategyWhitelister"
        );
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _initialOwner, address _fundingPodWhitelister) external initializer {
        __Ownable_init(_initialOwner);
        fundingPodWhitelister = _fundingPodWhitelister;
    }

    function depositEthIntoPod(IFundingPod fundingPod) external payable returns(bool) {
        return true;
    }

    function depositErc20IntoPod(IFundingPod fundingPod, IERC20 tokenAddress, uint256 amount) external {
        // todo：验证 Pod 是否在白名单

        tokenAddress.safeTransferFrom(msg.sender, address(fundingPod), amount);

        fundingPod.deposit(address(tokenAddress), amount);
    }


    function addStrategiesToDepositWhitelist(IFundingPod[] calldata fundingPodsToWhitelist, bool[] calldata thirdPartyTransfersForbiddenValues) external onlyFundingPodWhitelister {

    }

    function removeStrategiesFromDepositWhitelist(IFundingPod[] calldata fundingPodsToRemoveFromWhitelist) external onlyFundingPodWhitelister {

    }
}
