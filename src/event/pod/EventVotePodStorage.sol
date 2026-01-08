// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../interfaces/event/IEventVotePod.sol";

abstract contract EventVotePodStorage is IEventVotePod {
    
    // Manager address
    address public manager;
    
    // Voting token address
    address public votingToken;
    
    // Vote ID counter
    uint256 public voteIdCounter;
    
    // Mapping from vote ID to Vote struct
    mapping(uint256 => Vote) public votes;
    
    // Mapping from event ID to vote ID
    mapping(uint256 => uint256) public eventToVote;
    
    // Mapping from vote ID => voter address => last vote day
    mapping(uint256 => mapping(address => uint256)) public voterLastVoteDay;
    
    uint256[94] private __gap;
}
