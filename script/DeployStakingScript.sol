// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {EmptyContract} from "../src/utils/EmptyContract.sol";
import {ChooseMeToken} from "../src/token/ChooseMeToken.sol";
import {DaoRewardManager} from "../src/token/allocation/DaoRewardManager.sol";
import {FomoTreasureManager} from "../src/token/allocation/FomoTreasureManager.sol";
import {NodeManager} from "../src/staking/NodeManager.sol";
import {StakingManager} from "../src/staking/StakingManager.sol";
import {EventFundingManager} from "../src/staking/EventFundingManager.sol";
import {SubTokenFundingManager} from "../src/staking/SubTokenFundingManager.sol";

contract TestUSDT is ERC20 {
    constructor() ERC20("TestUSDT", "USDT") {
        _mint(msg.sender, 10000000 * 10 ** 18);
    }
}

// forge script DeployStakingScript --slow --multi --rpc-url https://bsc-dataseed.binance.org --broadcast --verify --etherscan-api-key I4C1AKJT8J9KJVCXHZKK317T3XV8IVASRX
// forge verify-contract --rpc-url https://bsc-dataseed.binance.org --etherscan-api-key I4C1AKJT8J9KJVCXHZKK317T3XV8IVASRX 0x97807b490Bb554a910f542693105d65742DaaAc9

contract DeployStakingScript is Script {
    EmptyContract public emptyContract;
    ProxyAdmin public chooseMeTokenProxyAdmin;
    ProxyAdmin public nodeManagerProxyAdmin;
    ProxyAdmin public stakingManagerProxyAdmin;
    ProxyAdmin public daoRewardManagerProxyAdmin;
    ProxyAdmin public fomoTreasureManagerProxyAdmin;
    ProxyAdmin public eventFundingManagerProxyAdmin;
    ProxyAdmin public subTokenFundingManagerProxyAdmin;

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

    SubTokenFundingManager public subTokenFundingManagerImplementation;
    SubTokenFundingManager public subTokenFundingManager;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        (
            address deployerAddress,
            address distributeRewardAddress,
            address chooseMeMultiSign,
            address usdtTokenAddress
        ) = getENVAddress(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        emptyContract = new EmptyContract();

        TransparentUpgradeableProxy proxyChooseMeToken =
            new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        chooseMeToken = ChooseMeToken(address(proxyChooseMeToken));
        chooseMeTokenImplementation = new ChooseMeToken();
        chooseMeTokenProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyChooseMeToken)));

        TransparentUpgradeableProxy proxyNodeManager =
            new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        nodeManager = NodeManager(payable(address(proxyNodeManager)));
        nodeManagerImplementation = new NodeManager();
        nodeManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyNodeManager)));

        TransparentUpgradeableProxy proxyStakingManager =
            new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        stakingManager = StakingManager(payable(address(proxyStakingManager)));
        stakingManagerImplementation = new StakingManager();
        stakingManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyStakingManager)));

        TransparentUpgradeableProxy proxyDaoRewardManager =
            new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        daoRewardManager = DaoRewardManager(payable(address(proxyDaoRewardManager)));
        daoRewardManagerImplementation = new DaoRewardManager();
        daoRewardManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyDaoRewardManager)));

        TransparentUpgradeableProxy proxyEventFundingManager =
            new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        eventFundingManager = EventFundingManager(payable(address(proxyEventFundingManager)));
        eventFundingManagerImplementation = new EventFundingManager();
        eventFundingManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyEventFundingManager)));

        TransparentUpgradeableProxy proxyFomoTreasureManager =
            new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        fomoTreasureManager = FomoTreasureManager(payable(address(proxyFomoTreasureManager)));
        fomoTreasureManagerImplementation = new FomoTreasureManager();
        fomoTreasureManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyFomoTreasureManager)));

        TransparentUpgradeableProxy proxySubTokenFundingManager =
            new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        subTokenFundingManager = SubTokenFundingManager(payable(address(proxySubTokenFundingManager)));
        subTokenFundingManagerImplementation = new SubTokenFundingManager();
        subTokenFundingManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxySubTokenFundingManager)));

        chooseMeTokenProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(chooseMeToken)),
            address(chooseMeTokenImplementation),
            abi.encodeWithSelector(
                ChooseMeToken.initialize.selector, chooseMeMultiSign, address(stakingManager), usdtTokenAddress
            )
        );

        nodeManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(nodeManager)),
            address(nodeManagerImplementation),
            abi.encodeWithSelector(
                NodeManager.initialize.selector,
                chooseMeMultiSign,
                address(daoRewardManager),
                address(chooseMeToken),
                usdtTokenAddress,
                distributeRewardAddress,
                address(eventFundingManager)
            )
        );

        stakingManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(stakingManager)),
            address(stakingManagerImplementation),
            abi.encodeWithSelector(
                StakingManager.initialize.selector,
                chooseMeMultiSign,
                address(chooseMeToken),
                usdtTokenAddress,
                distributeRewardAddress,
                address(daoRewardManager),
                address(eventFundingManager),
                address(nodeManager)
            )
        );

        daoRewardManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(daoRewardManager)),
            address(daoRewardManagerImplementation),
            abi.encodeWithSelector(
                DaoRewardManager.initialize.selector,
                chooseMeMultiSign,
                address(chooseMeToken),
                address(nodeManager),
                address(stakingManager)
            )
        );

        fomoTreasureManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(fomoTreasureManager)),
            address(fomoTreasureManagerImplementation),
            abi.encodeWithSelector(FomoTreasureManager.initialize.selector, chooseMeMultiSign, address(chooseMeToken))
        );

        eventFundingManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(eventFundingManager)),
            address(eventFundingManagerImplementation),
            abi.encodeWithSelector(EventFundingManager.initialize.selector, chooseMeMultiSign, usdtTokenAddress)
        );

        subTokenFundingManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(subTokenFundingManager)),
            address(subTokenFundingManagerImplementation),
            abi.encodeWithSelector(SubTokenFundingManager.initialize.selector, chooseMeMultiSign, usdtTokenAddress)
        );

        console.log("deploy usdtTokenAddress:", usdtTokenAddress);
        console.log("deploy proxyChooseMeToken:", address(proxyChooseMeToken));
        console.log("deploy proxyStakingManager:", address(proxyStakingManager));
        console.log("deploy proxyNodeManager:", address(proxyNodeManager));
        console.log("deploy proxyDaoRewardManager:", address(proxyDaoRewardManager));
        console.log("deploy proxyFomoTreasureManager:", address(proxyFomoTreasureManager));
        console.log("deploy proxyEventFundingManager:", address(proxyEventFundingManager));
        console.log("deploy proxySubTokenFundingManager:", address(proxySubTokenFundingManager));

        vm.stopBroadcast();

        string memory obj = "{}";
        vm.serializeAddress(obj, "usdtTokenAddress", usdtTokenAddress);
        vm.serializeAddress(obj, "proxyChooseMeToken", address(proxyChooseMeToken));
        vm.serializeAddress(obj, "proxyStakingManager", address(proxyStakingManager));
        vm.serializeAddress(obj, "proxyNodeManager", address(proxyNodeManager));
        vm.serializeAddress(obj, "proxyDaoRewardManager", address(proxyDaoRewardManager));
        vm.serializeAddress(obj, "proxyFomoTreasureManager", address(proxyFomoTreasureManager));
        vm.serializeAddress(obj, "proxyEventFundingManager", address(proxyEventFundingManager));
        string memory finalJSON =
            vm.serializeAddress(obj, "proxySubTokenFundingManager", address(proxySubTokenFundingManager));

        vm.writeJson(finalJSON, "./cache/__deployed_addresses.json");
    }

    function getProxyAdminAddress(address proxy) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }

    function getENVAddress(uint256 deployerPrivateKey)
        public
        returns (
            address deployerAddress,
            address distributeRewardAddress,
            address chooseMeMultiSign,
            address usdtTokenAddress
        )
    {
        uint256 mode = vm.envUint("MODE");
        deployerAddress = vm.addr(deployerPrivateKey);
        console.log("mode:", mode == 0 ? "development" : "production");
        if (mode == 0) {
            vm.startBroadcast(deployerPrivateKey);
            distributeRewardAddress = deployerAddress;
            chooseMeMultiSign = deployerAddress;
            ERC20 usdtToken = new TestUSDT();
            usdtTokenAddress = address(usdtToken);
            vm.stopBroadcast();
        } else {
            distributeRewardAddress = vm.envAddress("DR_ADDRESS");
            chooseMeMultiSign = vm.envAddress("MULTI_SIGNER");
            usdtTokenAddress = vm.envAddress("USDT_TOKEN_ADDRESS");
        }
    }
}
