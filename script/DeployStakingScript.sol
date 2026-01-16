// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import {Script, console} from "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {EmptyContract} from "../src/utils/EmptyContract.sol";
import {IChooseMeToken} from "../src/interfaces/token/IChooseMeToken.sol";
import {ChooseMeToken} from "../src/token/ChooseMeToken.sol";
import {DaoRewardManager} from "../src/token/allocation/DaoRewardManager.sol";
import {FomoTreasureManager} from "../src/token/allocation/FomoTreasureManager.sol";
import {AirdropManager} from "../src/token/allocation/AirdropManager.sol";
import {MarketManager} from "../src/token/allocation/MarketManager.sol";
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
    ProxyAdmin public marketManagerProxyAdmin;
    ProxyAdmin public airdropManagerProxyAdmin;

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

    MarketManager public marketManagerImplementation;
    MarketManager public marketManager;

    AirdropManager public airdropManagerImplementation;
    AirdropManager public airdropManager;

    TestUSDT public usdt;

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

        TransparentUpgradeableProxy proxyMarketManager =
            new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        marketManager = MarketManager(payable(address(proxyMarketManager)));
        marketManagerImplementation = new MarketManager();
        marketManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyMarketManager)));

        TransparentUpgradeableProxy proxyAirdropManager =
            new TransparentUpgradeableProxy(address(emptyContract), chooseMeMultiSign, "");
        airdropManager = AirdropManager(payable(address(proxyAirdropManager)));
        airdropManagerImplementation = new AirdropManager();
        airdropManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(address(proxyAirdropManager)));

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
                address(nodeManager),
                address(subTokenFundingManager)
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

        marketManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(marketManager)),
            address(marketManagerImplementation),
            abi.encodeWithSelector(MarketManager.initialize.selector, chooseMeMultiSign, usdtTokenAddress)
        );

        airdropManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(airdropManager)),
            address(airdropManagerImplementation),
            abi.encodeWithSelector(AirdropManager.initialize.selector, chooseMeMultiSign, usdtTokenAddress)
        );

        console.log("deploy usdtTokenAddress:", usdtTokenAddress);
        console.log("deploy proxyChooseMeToken:", address(proxyChooseMeToken));
        console.log("deploy proxyStakingManager:", address(proxyStakingManager));
        console.log("deploy proxyNodeManager:", address(proxyNodeManager));
        console.log("deploy proxyDaoRewardManager:", address(proxyDaoRewardManager));
        console.log("deploy proxyFomoTreasureManager:", address(proxyFomoTreasureManager));
        console.log("deploy proxyEventFundingManager:", address(proxyEventFundingManager));
        console.log("deploy proxySubTokenFundingManager:", address(proxySubTokenFundingManager));
        console.log("deploy proxyMarketManager:", address(proxyMarketManager));
        console.log("deploy proxyAirdropManager:", address(proxyAirdropManager));
        vm.stopBroadcast();

        string memory obj = "{}";
        vm.serializeAddress(obj, "usdtTokenAddress", usdtTokenAddress);
        vm.serializeAddress(obj, "proxyChooseMeToken", address(proxyChooseMeToken));
        vm.serializeAddress(obj, "proxyStakingManager", address(proxyStakingManager));
        vm.serializeAddress(obj, "proxyNodeManager", address(proxyNodeManager));
        vm.serializeAddress(obj, "proxyDaoRewardManager", address(proxyDaoRewardManager));
        vm.serializeAddress(obj, "proxyFomoTreasureManager", address(proxyFomoTreasureManager));
        vm.serializeAddress(obj, "proxyEventFundingManager", address(proxyEventFundingManager));
        vm.serializeAddress(obj, "proxyMarketManager", address(proxyMarketManager));
        vm.serializeAddress(obj, "proxyAirdropManager", address(proxyAirdropManager));

        string memory finalJSON =
            vm.serializeAddress(obj, "proxySubTokenFundingManager", address(proxySubTokenFundingManager));

        vm.writeJson(finalJSON, "./cache/__deployed_addresses.json");
    }

    // forge script DeployStakingScript --sig "update()"  --slow --multi --rpc-url https://bsc-dataseed.binance.org --broadcast
    function update() public {
        initContracts();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        nodeManagerImplementation = new NodeManager();
        nodeManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(nodeManager)), address(nodeManagerImplementation), ""
        );

        vm.stopBroadcast();
    }

    // forge script DeployStakingScript --sig "initChooseMeToken()"  --slow --multi --rpc-url https://bsc-dataseed.binance.org --broadcast
    function initChooseMeToken() public {
        initContracts();

        if (chooseMeToken.balanceOf(address(daoRewardManager)) > 0) return;
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        IChooseMeToken.ChooseMePool memory pools = IChooseMeToken.ChooseMePool({
            nodePool: vm.rememberKey(deployerPrivateKey),
            techRewardsPool: vm.rememberKey(deployerPrivateKey),
            foundingStrategyPool: vm.rememberKey(deployerPrivateKey),
            daoRewardPool: address(daoRewardManager),
            airdropPool: address(airdropManager),
            marketingPool: address(marketManager),
            subTokenPool: address(subTokenFundingManager)
        });

        address[] memory marketingPools = new address[](1);
        marketingPools[0] = vm.rememberKey(deployerPrivateKey);

        address[] memory ecosystemPools = new address[](1);
        ecosystemPools[0] = vm.rememberKey(deployerPrivateKey);

        chooseMeToken.setPoolAddress(pools, marketingPools, ecosystemPools);
        console.log("Pool addresses set");

        // Execute pool allocation
        chooseMeToken.poolAllocate();
        console.log("Pool allocation completed");
        console.log("Total Supply:", chooseMeToken.totalSupply() / 1e6, "CMT");

        vm.stopBroadcast();
    }

    function initContracts() internal {
        string memory json = vm.readFile("./cache/__deployed_addresses.json");
        address usdtTokenAddress = vm.parseJsonAddress(json, ".usdtTokenAddress");
        address proxyChooseMeToken = vm.parseJsonAddress(json, ".proxyChooseMeToken");
        address proxyStakingManager = vm.parseJsonAddress(json, ".proxyStakingManager");
        address proxyNodeManager = vm.parseJsonAddress(json, ".proxyNodeManager");
        address proxyDaoRewardManager = vm.parseJsonAddress(json, ".proxyDaoRewardManager");
        address proxyFomoTreasureManager = vm.parseJsonAddress(json, ".proxyFomoTreasureManager");
        address proxyEventFundingManager = vm.parseJsonAddress(json, ".proxyEventFundingManager");
        address proxyMarketManager = vm.parseJsonAddress(json, ".proxyMarketManager");
        address proxyAirdropManager = vm.parseJsonAddress(json, ".proxyAirdropManager");
        address proxySubTokenFundingManager = vm.parseJsonAddress(json, ".proxySubTokenFundingManager");

        usdt = TestUSDT(payable(usdtTokenAddress));
        chooseMeToken = ChooseMeToken(payable(proxyChooseMeToken));
        daoRewardManager = DaoRewardManager(payable(proxyDaoRewardManager));
        eventFundingManager = EventFundingManager(payable(proxyEventFundingManager));
        fomoTreasureManager = FomoTreasureManager(payable(proxyFomoTreasureManager));
        nodeManager = NodeManager(payable(proxyNodeManager));
        stakingManager = StakingManager(payable(proxyStakingManager));
        subTokenFundingManager = SubTokenFundingManager(payable(proxySubTokenFundingManager));
        marketManager = MarketManager(payable(proxyMarketManager));
        airdropManager = AirdropManager(payable(proxyAirdropManager));

        chooseMeTokenProxyAdmin = ProxyAdmin(getProxyAdminAddress(proxyChooseMeToken));
        nodeManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(proxyNodeManager));
        stakingManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(proxyStakingManager));
        daoRewardManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(proxyDaoRewardManager));
        fomoTreasureManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(proxyFomoTreasureManager));
        eventFundingManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(proxyEventFundingManager));
        subTokenFundingManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(proxySubTokenFundingManager));
        marketManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(proxyMarketManager));
        airdropManagerProxyAdmin = ProxyAdmin(getProxyAdminAddress(proxyAirdropManager));

        console.log("Contracts initialized");
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
