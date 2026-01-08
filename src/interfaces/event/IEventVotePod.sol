// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IEventVotePod {
    // Events
    event VoteInitialized(uint256 indexed voteId, uint256 indexed eventId, uint256 endTime, uint256 minBalance);
    event Voted(uint256 indexed voteId, address indexed voter, uint256 day);
    event VoteEnded(uint256 indexed voteId, uint256 indexed eventId, bool approved, uint256 totalVotes);
    
    // Errors
    error EventVotePod__NotManager();
    error EventVotePod__VoteNotActive();
    error EventVotePod__VoteEnded();
    error EventVotePod__AlreadyVotedToday();
    error EventVotePod__InsufficientBalance();
    error EventVotePod__AlreadyFinalized();
    
    // Structs
    struct Vote {
        uint256 voteId;
        uint256 eventId;
        uint256 startTime;
        uint256 endTime;
        uint256 minTokenBalance;    // Minimum token balance required to vote
        uint256 totalVotes;         // Total number of votes
        bool finalized;
        bool approved;
    }
    
    // Functions
    function initializeVote(
        uint256 eventId,
        uint256 votingPeriod,
        uint256 minTokenBalance
    ) external returns (uint256 voteId);
    
    function vote(uint256 voteId) external;
    
    function completeVote(uint256 voteId, bool approved) external;
    
    function getVoteDetails(uint256 voteId) external view returns (Vote memory);
    
    function hasVotedToday(uint256 voteId, address voter) external view returns (bool);
    
    function getVoterLastVoteDay(uint256 voteId, address voter) external view returns (uint256 day);
}
