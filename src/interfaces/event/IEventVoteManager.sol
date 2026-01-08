// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IEventVoteManager {
    // Events
    event VoteCreated(uint256 indexed eventId, address indexed pod, uint256 voteId);
    event VoteCompleted(address indexed pod, uint256 indexed voteId, uint256 indexed eventId, bool approved);
    
    // Errors
    error EventVoteManager__InvalidPod();
    error EventVoteManager__VoteNotExist();
    error EventVoteManager__VoteNotCompleted();
    
    // Functions
    function createVote(
        uint256 eventId, 
        address pod,
        uint256 votingPeriod,
        uint256 minTokenBalance
    ) external returns (uint256 voteId);
    
    function completeVote(address pod, uint256 voteId, bool approved) external;
}
