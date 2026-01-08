// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/event/core/EventVoteManager.sol";
import "../src/event/pod/EventVotePod.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock EventManager for testing
contract MockEventManager {
    event EventPublished(uint256 indexed eventId, address indexed publisher);
    
    function publishEvent(uint256 eventId) external {
        emit EventPublished(eventId, msg.sender);
    }
}

contract TestEventVote is Test {
    EventVoteManager public voteManager;
    EventVotePod public votePod;
    MockERC20 public votingToken;
    MockEventManager public eventManager;
    
    address public owner = address(this);
    address public caller = address(0x99);
    address public voter1 = address(0x1);
    address public voter2 = address(0x2);
    address public voter3 = address(0x3);
    
    uint256 constant VOTING_PERIOD = 7 days;
    uint256 constant MIN_TOKEN_BALANCE = 100 * 10**18;
    
    function setUp() public {
        // Deploy mock contracts
        votingToken = new MockERC20();
        eventManager = new MockEventManager();
        
        // Deploy EventVoteManager
        EventVoteManager voteManagerImpl = new EventVoteManager();
        bytes memory managerInitData = abi.encodeWithSelector(
            EventVoteManager.initialize.selector,
            address(eventManager),
            caller
        );
        ERC1967Proxy voteManagerProxy = new ERC1967Proxy(
            address(voteManagerImpl),
            managerInitData
        );
        voteManager = EventVoteManager(address(voteManagerProxy));
        
        // Deploy EventVotePod
        EventVotePod votePodImpl = new EventVotePod();
        bytes memory podInitData = abi.encodeWithSelector(
            EventVotePod.initialize.selector,
            address(voteManager),
            address(votingToken)
        );
        ERC1967Proxy votePodProxy = new ERC1967Proxy(
            address(votePodImpl),
            podInitData
        );
        votePod = EventVotePod(address(votePodProxy));
        
        // Add pod to manager
        voteManager.addPod(address(votePod));
        
        // Mint tokens to voters
        votingToken.mint(voter1, 1000 * 10**18);
        votingToken.mint(voter2, 2000 * 10**18);
        votingToken.mint(voter3, 3000 * 10**18);
    }
    
    function testCreateVote() public {
        uint256 eventId = 1;
        
        vm.prank(caller);
        uint256 voteId = voteManager.createVote(
            eventId,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        assertEq(voteId, 1);
        
        // Check vote details from pod
        IEventVotePod.Vote memory voteDetails = voteManager.getVoteInfo(address(votePod), voteId);
        assertEq(voteDetails.eventId, eventId);
        assertEq(voteDetails.voteId, voteId);
        assertEq(voteDetails.minTokenBalance, MIN_TOKEN_BALANCE);
        assertFalse(voteDetails.finalized);
        assertFalse(voteDetails.approved);
    }
    
    function testVoting() public {
        // Create vote
        uint256 eventId = 1;
        vm.prank(caller);
        uint256 voteId = voteManager.createVote(
            eventId,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        // Voter1 votes
        vm.prank(voter1);
        votePod.vote(voteId);
        
        // Voter2 votes
        vm.prank(voter2);
        votePod.vote(voteId);
        
        // Check vote details
        IEventVotePod.Vote memory voteDetails = votePod.getVoteDetails(voteId);
        assertEq(voteDetails.totalVotes, 2);
        
        // Check has voted today
        assertTrue(votePod.hasVotedToday(voteId, voter1));
        assertTrue(votePod.hasVotedToday(voteId, voter2));
        assertFalse(votePod.hasVotedToday(voteId, voter3));
    }
    
    function testVoteDailyRenewal() public {
        // Create vote
        uint256 eventId = 1;
        vm.prank(caller);
        uint256 voteId = voteManager.createVote(
            eventId,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        // Voter1 votes on day 1
        vm.prank(voter1);
        votePod.vote(voteId);
        
        IEventVotePod.Vote memory voteDetails = votePod.getVoteDetails(voteId);
        assertEq(voteDetails.totalVotes, 1);
        
        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        // Voter1 can vote again
        vm.prank(voter1);
        votePod.vote(voteId);
        
        // Total should still be 1 (same voter)
        voteDetails = votePod.getVoteDetails(voteId);
        assertEq(voteDetails.totalVotes, 1);
    }
    
    function testCompleteVoteApproved() public {
        // Create vote
        uint256 eventId = 1;
        vm.prank(caller);
        uint256 voteId = voteManager.createVote(
            eventId,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        // Voters vote
        vm.prank(voter1);
        votePod.vote(voteId);
        
        vm.prank(voter2);
        votePod.vote(voteId);
        
        vm.prank(voter3);
        votePod.vote(voteId);
        
        // Manager completes vote with approval
        vm.prank(caller);
        voteManager.completeVote(address(votePod), voteId, true);
        
        // Check vote is approved
        IEventVotePod.Vote memory voteDetails = votePod.getVoteDetails(voteId);
        assertTrue(voteDetails.finalized);
        assertTrue(voteDetails.approved);
        assertEq(voteDetails.totalVotes, 3);
    }
    
    function testCompleteVoteRejected() public {
        // Create vote
        uint256 eventId = 1;
        vm.prank(caller);
        uint256 voteId = voteManager.createVote(
            eventId,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        // Only one voter
        vm.prank(voter1);
        votePod.vote(voteId);
        
        // Manager rejects vote
        vm.prank(caller);
        voteManager.completeVote(address(votePod), voteId, false);
        
        // Check vote is rejected
        IEventVotePod.Vote memory voteDetails = votePod.getVoteDetails(voteId);
        assertTrue(voteDetails.finalized);
        assertFalse(voteDetails.approved);
    }
    
    function testCannotVoteAfterPeriodEnds() public {
        // Create vote
        uint256 eventId = 1;
        vm.prank(caller);
        uint256 voteId = voteManager.createVote(
            eventId,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        // Fast forward time past voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        
        // Try to vote - should revert
        vm.prank(voter1);
        vm.expectRevert(IEventVotePod.EventVotePod__VoteEnded.selector);
        votePod.vote(voteId);
    }
    
    function testCannotVoteTwiceInSameDay() public {
        // Create vote
        uint256 eventId = 1;
        vm.prank(caller);
        uint256 voteId = voteManager.createVote(
            eventId,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        // Voter1 votes
        vm.prank(voter1);
        votePod.vote(voteId);
        
        // Voter1 tries to vote again same day - should revert
        vm.prank(voter1);
        vm.expectRevert(IEventVotePod.EventVotePod__AlreadyVotedToday.selector);
        votePod.vote(voteId);
    }
    
    function testCannotVoteWithInsufficientBalance() public {
        // Create vote with high min balance
        uint256 eventId = 1;
        vm.prank(caller);
        uint256 voteId = voteManager.createVote(
            eventId,
            address(votePod),
            VOTING_PERIOD,
            5000 * 10**18  // Higher than voter1's balance
        );
        
        // Try to vote with insufficient balance - should revert
        vm.prank(voter1);
        vm.expectRevert(IEventVotePod.EventVotePod__InsufficientBalance.selector);
        votePod.vote(voteId);
    }
    
    function testCannotVoteAfterFinalized() public {
        // Create vote
        uint256 eventId = 1;
        vm.prank(caller);
        uint256 voteId = voteManager.createVote(
            eventId,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        // Complete vote
        vm.prank(caller);
        voteManager.completeVote(address(votePod), voteId, true);
        
        // Try to vote after finalized - should revert
        vm.prank(voter1);
        vm.expectRevert(IEventVotePod.EventVotePod__AlreadyFinalized.selector);
        votePod.vote(voteId);
    }
    
    function testCannotCompleteVoteTwice() public {
        // Create vote
        uint256 eventId = 1;
        vm.prank(caller);
        uint256 voteId = voteManager.createVote(
            eventId,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        // Complete vote first time
        vm.prank(caller);
        voteManager.completeVote(address(votePod), voteId, true);
        
        // Try to complete again - should revert
        vm.prank(caller);
        vm.expectRevert(IEventVotePod.EventVotePod__AlreadyFinalized.selector);
        voteManager.completeVote(address(votePod), voteId, false);
    }
    
    function testEventPublishedOnApproval() public {
        // Create vote
        uint256 eventId = 1;
        vm.prank(caller);
        uint256 voteId = voteManager.createVote(
            eventId,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        // Expect EventPublished event
        vm.expectEmit(true, true, false, false);
        emit MockEventManager.EventPublished(eventId, address(voteManager));
        
        // Complete vote with approval
        vm.prank(caller);
        voteManager.completeVote(address(votePod), voteId, true);
    }
    
    function testMultipleVotes() public {
        // Create multiple votes
        uint256 eventId1 = 1;
        uint256 eventId2 = 2;
        
        vm.prank(caller);
        uint256 voteId1 = voteManager.createVote(
            eventId1,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        vm.prank(caller);
        uint256 voteId2 = voteManager.createVote(
            eventId2,
            address(votePod),
            VOTING_PERIOD,
            MIN_TOKEN_BALANCE
        );
        
        assertEq(voteId1, 1);
        assertEq(voteId2, 2);
        
        // Vote on both
        vm.prank(voter1);
        votePod.vote(voteId1);
        
        vm.prank(voter1);
        votePod.vote(voteId2);
        
        // Check both votes
        IEventVotePod.Vote memory vote1 = votePod.getVoteDetails(voteId1);
        IEventVotePod.Vote memory vote2 = votePod.getVoteDetails(voteId2);
        
        assertEq(vote1.totalVotes, 1);
        assertEq(vote2.totalVotes, 1);
    }
}
