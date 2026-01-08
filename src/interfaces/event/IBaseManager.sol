// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IBaseManager {
    // Events
    event PodWhitelisted(uint256 indexed projectId, address indexed podAddress);
    event PodRemovedFromWhitelist(uint256 indexed projectId, address indexed podAddress);
    event ProjectRegistrySet(address indexed projectRegistry);

    // Functions
    function setProjectRegistry(address _projectRegistry) external;

    function addPodToWhitelist(uint256 _projectId, address _podAddress) external;

    function removePodFromWhitelist(uint256 _projectId) external;

    function isPodWhitelisted(uint256 _projectId) external view returns (bool);

    function getPodAddress(uint256 _projectId) external view returns (address);

    function getWhitelistedProjects() external view returns (uint256[] memory);

    function getWhitelistedProjectCount() external view returns (uint256);

    // State variables
    function projectRegistry() external view returns (address);
    
    function projectToPod(uint256 projectId) external view returns (address);
}
