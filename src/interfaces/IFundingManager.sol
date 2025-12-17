// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IFundingPod.sol";

interface IFundingManager {
    function depositEthIntoPod(IFundingPod fundingPod) external payable returns(bool);
    function depositErc20IntoPod(IFundingPod fundingPod, IERC20 tokenAddress, uint256 amount) external;


    function addStrategiesToDepositWhitelist(
        IFundingPod[] calldata fundingPodsToWhitelist,
        bool[] calldata thirdPartyTransfersForbiddenValues
    ) external;

    function removeStrategiesFromDepositWhitelist(
        IFundingPod[] calldata fundingPodsToRemoveFromWhitelist
    ) external;

}
