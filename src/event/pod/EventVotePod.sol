// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./EventVotePodStorage.sol";
import "../../interfaces/event/IEventVoteManager.sol";

contract EventVotePod is Initializable, OwnableUpgradeable, EventVotePodStorage {
    using SafeERC20 for IERC20;
    
    modifier onlyManager() {
        if (msg.sender != manager) {
            revert EventVotePod__NotManager();
        }
        _;
    }
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(address _manager, address _votingToken) public initializer {
        __Ownable_init(msg.sender);
        manager = _manager;
        votingToken = _votingToken;
        voteIdCounter = 1;
    }
    
    /**
     * @dev Initialize a new vote
     * @param eventId The event ID to vote on
     * @param votingPeriod The voting period in seconds
     * @param minTokenBalance The minimum token balance required to vote
     * @return voteId The created vote ID
     */
    function initializeVote(
        uint256 eventId,
        uint256 votingPeriod,
        uint256 minTokenBalance
    ) external onlyManager returns (uint256 voteId) {
        // Check if event already has a vote
        if (eventToVote[eventId] != 0) {
            revert EventVotePod__VoteNotActive();
        }
        
        voteId = voteIdCounter++;
        eventToVote[eventId] = voteId;
        
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + votingPeriod;
        
        votes[voteId] = Vote({
            voteId: voteId,
            eventId: eventId,
            startTime: startTime,
            endTime: endTime,
            minTokenBalance: minTokenBalance,
            totalVotes: 0,
            finalized: false,
            approved: false
        });
        
        emit VoteInitialized(voteId, eventId, endTime, minTokenBalance);
        
        return voteId;
    }
    
    /**
     * @dev Cast a vote (can vote once per day, only support votes)
     * @param voteId The vote ID
     */
    function vote(uint256 voteId) external {
        Vote storage voteData = votes[voteId];
        
        // Check vote exists and is active
        if (voteData.voteId == 0) {
            revert EventVotePod__VoteNotActive();
        }
        
        if (block.timestamp >= voteData.endTime) {
            revert EventVotePod__VoteEnded();
        }
        
        if (voteData.finalized) {
            revert EventVotePod__AlreadyFinalized();
        }
        
        // Check voter has minimum token balance
        uint256 voterBalance = IERC20(votingToken).balanceOf(msg.sender);
        if (voterBalance < voteData.minTokenBalance) {
            revert EventVotePod__InsufficientBalance();
        }
        
        // Calculate current day (days since Unix epoch, +1 to avoid 0)
        uint256 currentDay = block.timestamp / 1 days + 1;
        uint256 lastVoteDay = voterLastVoteDay[voteId][msg.sender];
        
        // Check if already voted today
        if (lastVoteDay == currentDay) {
            revert EventVotePod__AlreadyVotedToday();
        }
        
        // If voted before on a different day, don't count as new vote
        if (lastVoteDay == 0) {
            // First time voting, increment total
            voteData.totalVotes += 1;
        }
        
        // Record vote day
        voterLastVoteDay[voteId][msg.sender] = currentDay;
        
        emit Voted(voteId, msg.sender, currentDay);
    }
    
    /**
     * @dev End a vote manually by manager
     * @param voteId The vote ID to end
     * @param approved Whether the vote is approved by manager
     */
    function completeVote(uint256 voteId, bool approved) external onlyManager {
        Vote storage voteData = votes[voteId];
        
        if (voteData.voteId == 0) {
            revert EventVotePod__VoteNotActive();
        }
        
        if (voteData.finalized) {
            revert EventVotePod__AlreadyFinalized();
        }
        
        voteData.finalized = true;
        voteData.approved = approved;
        
        emit VoteEnded(voteId, voteData.eventId, approved, voteData.totalVotes);
    }
    
    /**
     * @dev Get vote details
     * @param voteId The vote ID
     * @return Vote struct with all vote information
     */
    function getVoteDetails(uint256 voteId) external view returns (Vote memory) {
        return votes[voteId];
    }
    
    /**
     * @dev Check if an address has voted today
     * @param voteId The vote ID
     * @param voter The voter address
     * @return True if the voter has voted today
     */
    function hasVotedToday(uint256 voteId, address voter) external view returns (bool) {
        uint256 currentDay = block.timestamp / 1 days + 1;
        return voterLastVoteDay[voteId][voter] == currentDay;
    }
    
    /**
     * @dev Get voter's last vote day
     * @param voteId The vote ID
     * @param voter The voter address
     * @return day The day of the last vote (0 if never voted)
     */
    function getVoterLastVoteDay(uint256 voteId, address voter) 
        external 
        view 
        returns (uint256 day) 
    {
        return voterLastVoteDay[voteId][voter];
    }
}
