// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { EmptyContract } from "../src/utils/EmptyContract.sol";
import { ChooseMeToken } from "../src/token/ChooseMeToken.sol";
import { NodeManager } from "../src/staking/NodeManager.sol";
import { StakingManager } from "../src/staking/StakingManager.sol";
import { DaoRewardManager } from "../src/token/allocation/DaoRewardManager.sol";
import { FomoTreasureManager } from "../src/token/allocation/FomoTreasureManager.sol";
import { EventFundingManager } from "../src/staking/EventFundingManager.sol";


contract DeployStakingScript is Script {
    EmptyContract public emptyContract;
    ProxyAdmin public chooseMeTokenProxyAdmin;
    ProxyAdmin public nodeManagerProxyAdmin;
    ProxyAdmin public stakingManagerProxyAdmin;
    ProxyAdmin public daoRewardManagerProxyAdmin;
    ProxyAdmin public fomoTreasureManagerProxyAdmin;
    ProxyAdmin public eventFundingManagerProxyAdmin;

    ChooseMeToken public chooseMeTokenImplementation;
    ChooseMeToken public chooseMeToken;

    NodeManager public nodeManagerImplementation;
    NodeManager public nodeManager;

    StakingManager public stakingManagerImplementation;
    StakingManager public stakingManager;

    DaoRewardManager public daoRewardManagerImplementation;
    DaoRewardManager public daoRewardManager;

    FomoTreasureManager public fomoTreasureManagerImplementation;
    FomoTreasureManager public fomoTreasureManager;

    EventFundingManager public eventFundingManagerImplementation;
    EventFundingManager public eventFundingManager;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address distributeRewardAddress =  vm.envAddress("DR_ADDRESS");
        address chooseMeMultiSign = vm.envAddress("MULTI_SIGNER");
        address usdtTokenAddress = vm.envAddress("USDT_TOKEN_ADDRESS");

        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        emptyContract = new EmptyContract();

        TransparentUpgradeableProxy proxyChooseMeToken = new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        chooseMeToken = ChooseMeToken(address(proxyChooseMeToken));
        chooseMeTokenImplementation = new ChooseMeToken();
        chooseMeTokenProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyChooseMeToken)));

        TransparentUpgradeableProxy proxyNodeManager = new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        nodeManager = NodeManager(payable(address(proxyNodeManager)));
        nodeManagerImplementation = new NodeManager();
        nodeManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyNodeManager)));

        TransparentUpgradeableProxy proxyStakingManager = new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        stakingManager = StakingManager(payable(address(proxyStakingManager)));
        stakingManagerImplementation = new StakingManager();
        stakingManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyStakingManager)));

        TransparentUpgradeableProxy proxyDaoRewardManager = new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        daoRewardManager = DaoRewardManager(payable(address(proxyDaoRewardManager)));
        daoRewardManagerImplementation = new DaoRewardManager();
        daoRewardManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyDaoRewardManager)));

        TransparentUpgradeableProxy proxyEventFundingManager = new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        eventFundingManager = EventFundingManager(payable(address(proxyEventFundingManager)));
        eventFundingManagerImplementation = new EventFundingManager();
        eventFundingManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyEventFundingManager)));

        TransparentUpgradeableProxy proxyFomoTreasureManager = new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        fomoTreasureManager = FomoTreasureManager(payable(address(proxyFomoTreasureManager)));
        fomoTreasureManagerImplementation = new FomoTreasureManager();
        fomoTreasureManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyFomoTreasureManager)));

        chooseMeTokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(chooseMeToken)),
            address(chooseMeTokenImplementation),
            abi.encodeWithSelector(
                FomoTreasureManager.initialize.selector,
                deployerAddress,
                address(daoRewardManager)
            )
        );

        nodeManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(nodeManager)),
            address(nodeManagerImplementation),
            abi.encodeWithSelector(
                NodeManager.initialize.selector,
                deployerAddress,
                address(daoRewardManager),
                address(chooseMeToken),
                distributeRewardAddress,
                address(eventFundingManager)
            )
        );

        stakingManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(stakingManager)),
            address(stakingManagerImplementation),
            abi.encodeWithSelector(
                StakingManager.initialize.selector,
                deployerAddress,
                address(chooseMeToken),
                chooseMeMultiSign,
                address(daoRewardManager),
                address(eventFundingManager)
            )
        );

        daoRewardManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(daoRewardManager)),
            address(daoRewardManagerImplementation),
            abi.encodeWithSelector(
                DaoRewardManager.initialize.selector,
                deployerAddress,
                address(chooseMeToken)
            )
        );

        fomoTreasureManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(fomoTreasureManager)),
            address(fomoTreasureManagerImplementation),
            abi.encodeWithSelector(
                FomoTreasureManager.initialize.selector,
                deployerAddress,
                address(chooseMeToken)
            )
        );

        eventFundingManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(eventFundingManager)),
            address(eventFundingManagerImplementation),
            abi.encodeWithSelector(
                EventFundingManager.initialize.selector,
                deployerAddress,
                usdtTokenAddress
            )
        );

        console.log("deploy proxyChooseMeToken:", address(proxyChooseMeToken));
        console.log("deploy proxyStakingManager:", address(proxyStakingManager));
        console.log("deploy proxyNodeManager:", address(proxyNodeManager));
        console.log("deploy proxyDaoRewardManager:", address(proxyDaoRewardManager));
        console.log("deploy proxyFomoTreasureManager:", address(proxyFomoTreasureManager));

        vm.stopBroadcast();
    }


    function getProxyAdminAddress(address proxy) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
}
