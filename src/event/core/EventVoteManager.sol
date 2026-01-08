// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./EventVoteManagerStorage.sol";
import "../common/BaseManager.sol";
import "../../interfaces/event/IEventManager.sol";
import "../../interfaces/event/IEventVotePod.sol";

contract EventVoteManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    BaseManager,
    EventVoteManagerStorage
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    modifier onlyCaller() {
        require(msg.sender == caller, "EventVoteManager: caller only");
        _;
    }

    function initialize(address _eventManager, address _caller) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();

        eventManager = _eventManager;
        caller = _caller;
    }

    /**
     * @dev Create a new vote for an event
     * @param eventId The event ID to vote on
     * @param pod The EventVotePod contract address
     * @param votingPeriod The voting period in seconds
     * @param minTokenBalance The minimum token balance required to vote
     * @return voteId The created vote ID
     */
    function createVote(
        uint256 eventId,
        address pod,
        uint256 votingPeriod,
        uint256 minTokenBalance
    ) external onlyCaller onlyPod(pod) whenNotPaused returns (uint256 voteId) {
        if (!isPod(pod)) {
            revert EventVoteManager__InvalidPod();
        }

        // Call pod to initialize vote
        voteId = IEventVotePod(pod).initializeVote(
            eventId,
            votingPeriod,
            minTokenBalance
        );

        emit VoteCreated(eventId, pod, voteId);

        return voteId;
    }

    /**
     * @dev Complete a vote and publish event if approved
     * @param pod The pod address
     * @param voteId The vote ID
     * @param approved Whether the vote was approved
     */
    function completeVote(address pod, uint256 voteId, bool approved) external onlyCaller whenNotPaused {
        if (!isPod(pod)) {
            revert EventVoteManager__InvalidPod();
        }
        
        // Call pod to complete vote
        IEventVotePod(pod).completeVote(voteId, approved);
        
        // Get vote details from pod
        IEventVotePod.Vote memory voteData = IEventVotePod(pod).getVoteDetails(voteId);
        
        if (voteData.voteId == 0) {
            revert EventVoteManager__VoteNotExist();
        }

        emit VoteCompleted(pod, voteId, voteData.eventId, approved);

        // If approved, publish event to EventManager
        if (approved) {
            // TODO :add publish event logic
            // IEventManager(eventManager).publishEvent(voteData.eventId);
        }
    }

    /**
     * @dev Get vote information from a specific pod
     * @param pod The pod address
     * @param voteId The vote ID
     * @return Vote details
     */
    function getVoteInfo(address pod, uint256 voteId)
        external
        view
        returns (IEventVotePod.Vote memory)
    {
        return IEventVotePod(pod).getVoteDetails(voteId);
    }

    /**
     * @dev Set event manager address
     * @param _eventManager New event manager address
     */
    function setEventManager(address _eventManager) external onlyOwner {
        eventManager = _eventManager;
    }
    
    /**
     * @dev Set caller address
     * @param _caller New caller address
     */
    function setCaller(address _caller) external onlyOwner {
        caller = _caller;
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
