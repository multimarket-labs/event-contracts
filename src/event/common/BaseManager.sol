// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "./BaseManagerStorage.sol";

abstract contract BaseManager is Initializable, OwnableUpgradeable, BaseManagerStorage {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Events
    event AddPod(address indexed podAddress);
    event RemovePod(address indexed podAddress);

    modifier onlyPod(address _pod) {
        require(isPod(_pod), "BaseManager: Pod is not whitelisted");
        _;
    }

    function addPod(address _pod) external onlyOwner {
        if (!pods.contains(_pod)) {
            pods.add(_pod);
            emit AddPod(_pod);
        }
    }

    function removePod(address _pod) external onlyOwner {
        if (pods.contains(_pod)) {
            pods.remove(_pod);
            emit RemovePod(_pod);
        }
    }

    function isPod(address _pod) public view returns (bool) {
        return pods.contains(_pod);
    }

    function getPods() external view returns (address[] memory) {
        return pods.values();
    }
}
