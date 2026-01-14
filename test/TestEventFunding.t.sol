// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/event/core/FundingManager.sol";
import "../src/event/pod/FundingPod.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock EventPod for testing
contract MockEventPod {
    event ReceivedETH(uint256 amount);
    event ReceivedToken(address token, uint256 amount);

    receive() external payable {
        emit ReceivedETH(msg.value);
    }

    function receiveToken(address token, uint256 amount) external {
        emit ReceivedToken(token, amount);
    }
}

contract TestEventFunding is Test {
    FundingManager public fundingManager;
    FundingPod public fundingPod;
    MockERC20 public mockToken;
    MockEventPod public mockEventPod;

    address public owner = address(this);
    address public authorizedCaller = address(0x99);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    address public constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event TransferToEvent(address indexed eventPod, address indexed token, address indexed user, uint256 amount);
    event ReceiveFromEvent(address indexed eventPod, address indexed token, address indexed user, uint256 amount);
    event EventPodUpdated(address indexed oldEventPod, address indexed newEventPod);
    event AuthorizedCallerAdded(address indexed caller);
    event AuthorizedCallerRemoved(address indexed caller);

    function setUp() public {
        // Deploy mock contracts
        mockToken = new MockERC20();
        mockEventPod = new MockEventPod();

        // Deploy FundingManager
        FundingManager fundingManagerImpl = new FundingManager();
        bytes memory managerInitData = abi.encodeWithSelector(FundingManager.initialize.selector, owner);
        ERC1967Proxy fundingManagerProxy = new ERC1967Proxy(address(fundingManagerImpl), managerInitData);
        fundingManager = FundingManager(payable(address(fundingManagerProxy)));

        // Deploy FundingPod
        FundingPod fundingPodImpl = new FundingPod();
        bytes memory podInitData = abi.encodeWithSelector(
            FundingPod.initialize.selector, owner, address(fundingManager), address(mockEventPod)
        );
        ERC1967Proxy fundingPodProxy = new ERC1967Proxy(address(fundingPodImpl), podInitData);
        fundingPod = FundingPod(payable(address(fundingPodProxy)));

        // Add pod to manager
        fundingManager.addPod(address(fundingPod));

        // Add supported tokens
        fundingManager.addSupportToken(address(fundingPod), ETH_ADDRESS);
        fundingManager.addSupportToken(address(fundingPod), address(mockToken));

        // Give users some ETH and tokens
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);

        mockToken.mint(user1, 10000 * 10 ** 18);
        mockToken.mint(user2, 20000 * 10 ** 18);
        mockToken.mint(user3, 30000 * 10 ** 18);
    }

    // ==================== FundingManager Tests ====================

    function testFundingManagerInitialize() public {
        assertEq(fundingManager.owner(), owner);
        assertTrue(fundingManager.isPod(address(fundingPod)));
    }

    function testAddAuthorizedCaller() public {
        vm.expectEmit(true, false, false, false);
        emit AuthorizedCallerAdded(authorizedCaller);

        fundingManager.addAuthorizedCaller(authorizedCaller);

        assertTrue(fundingManager.isAuthorizedCaller(authorizedCaller));
    }

    function testRemoveAuthorizedCaller() public {
        fundingManager.addAuthorizedCaller(authorizedCaller);
        assertTrue(fundingManager.isAuthorizedCaller(authorizedCaller));

        vm.expectEmit(true, false, false, false);
        emit AuthorizedCallerRemoved(authorizedCaller);

        fundingManager.removeAuthorizedCaller(authorizedCaller);

        assertFalse(fundingManager.isAuthorizedCaller(authorizedCaller));
    }

    function testGetAuthorizedCallers() public {
        fundingManager.addAuthorizedCaller(authorizedCaller);
        fundingManager.addAuthorizedCaller(user1);

        address[] memory callers = fundingManager.getAuthorizedCallers();
        assertEq(callers.length, 2);
    }

    function testAddSupportToken() public {
        address newToken = address(0x999);

        fundingManager.addSupportToken(address(fundingPod), newToken);

        assertTrue(fundingPod.isSupportToken(newToken));
    }

    function testRemoveSupportToken() public {
        fundingManager.removeSupportToken(address(fundingPod), address(mockToken));

        assertFalse(fundingPod.isSupportToken(address(mockToken)));
    }

    function testSetEventPod() public {
        address newEventPod = address(0x888);

        vm.expectEmit(true, true, false, false);
        emit EventPodUpdated(address(mockEventPod), newEventPod);

        fundingManager.setEventPod(address(fundingPod), newEventPod);

        assertEq(fundingPod.eventPod(), newEventPod);
    }

    function testOnlyOwnerCanAddAuthorizedCaller() public {
        vm.prank(user1);
        vm.expectRevert();
        fundingManager.addAuthorizedCaller(authorizedCaller);
    }

    function testCannotAddZeroAddressAsAuthorizedCaller() public {
        vm.expectRevert(FundingManager.InvalidAddress.selector);
        fundingManager.addAuthorizedCaller(address(0));
    }

    function testOnlyOwnerCanManagePods() public {
        address newPod = address(0x777);

        vm.prank(user1);
        vm.expectRevert();
        fundingManager.addPod(newPod);
    }

    function testCannotManageUnregisteredPod() public {
        address unregisteredPod = address(0x666);

        vm.expectRevert();
        fundingManager.addSupportToken(unregisteredPod, address(mockToken));
    }

    // ==================== FundingPod Tests ====================

    function testFundingPodInitialize() public {
        assertEq(fundingPod.owner(), owner);
        assertEq(fundingPod.fundingManager(), address(fundingManager));
        assertEq(fundingPod.eventPod(), address(mockEventPod));
        assertTrue(fundingPod.isSupportToken(ETH_ADDRESS));
        assertTrue(fundingPod.isSupportToken(address(mockToken)));
    }

    function testDepositETH() public {
        uint256 depositAmount = 10 ether;

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, ETH_ADDRESS, depositAmount);

        fundingPod.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);

        assertEq(fundingPod.getUserBalance(user1, ETH_ADDRESS), depositAmount);
        assertEq(fundingPod.tokenBalances(ETH_ADDRESS), depositAmount);
        assertEq(address(fundingPod).balance, depositAmount);
    }

    function testDepositERC20() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        vm.startPrank(user1);
        mockToken.approve(address(fundingPod), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, address(mockToken), depositAmount);

        fundingPod.deposit(address(mockToken), depositAmount);
        vm.stopPrank();

        assertEq(fundingPod.getUserBalance(user1, address(mockToken)), depositAmount);
        assertEq(fundingPod.tokenBalances(address(mockToken)), depositAmount);
        assertEq(mockToken.balanceOf(address(fundingPod)), depositAmount);
    }

    function testWithdrawETH() public {
        uint256 depositAmount = 10 ether;
        uint256 withdrawAmount = 3 ether;

        vm.startPrank(user1);
        fundingPod.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);

        uint256 balanceBefore = user1.balance;

        vm.expectEmit(true, true, false, true);
        emit Withdraw(user1, ETH_ADDRESS, withdrawAmount);

        fundingPod.withdraw(ETH_ADDRESS, withdrawAmount);
        vm.stopPrank();

        assertEq(fundingPod.getUserBalance(user1, ETH_ADDRESS), depositAmount - withdrawAmount);
        assertEq(fundingPod.tokenBalances(ETH_ADDRESS), depositAmount - withdrawAmount);
        assertEq(user1.balance - balanceBefore, withdrawAmount);
    }

    function testWithdrawERC20() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 300 * 10 ** 18;

        vm.startPrank(user1);
        mockToken.approve(address(fundingPod), depositAmount);
        fundingPod.deposit(address(mockToken), depositAmount);

        uint256 balanceBefore = mockToken.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit Withdraw(user1, address(mockToken), withdrawAmount);

        fundingPod.withdraw(address(mockToken), withdrawAmount);
        vm.stopPrank();

        assertEq(fundingPod.getUserBalance(user1, address(mockToken)), depositAmount - withdrawAmount);
        assertEq(fundingPod.tokenBalances(address(mockToken)), depositAmount - withdrawAmount);
        assertEq(mockToken.balanceOf(user1) - balanceBefore, withdrawAmount);
    }

    function testTransferToEventETH() public {
        uint256 depositAmount = 10 ether;
        uint256 transferAmount = 3 ether;

        // User deposits
        vm.prank(user1);
        fundingPod.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);

        // EventPod transfers to event
        vm.prank(address(mockEventPod));
        vm.expectEmit(true, true, true, true);
        emit TransferToEvent(address(mockEventPod), ETH_ADDRESS, user1, transferAmount);

        fundingPod.transferToEvent(ETH_ADDRESS, user1, transferAmount);

        assertEq(fundingPod.getUserBalance(user1, ETH_ADDRESS), depositAmount - transferAmount);
        assertEq(fundingPod.tokenBalances(ETH_ADDRESS), depositAmount - transferAmount);
        assertEq(address(mockEventPod).balance, transferAmount);
    }

    function testTransferToEventERC20() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 transferAmount = 300 * 10 ** 18;

        // User deposits
        vm.startPrank(user1);
        mockToken.approve(address(fundingPod), depositAmount);
        fundingPod.deposit(address(mockToken), depositAmount);
        vm.stopPrank();

        // EventPod transfers to event
        vm.prank(address(mockEventPod));
        vm.expectEmit(true, true, true, true);
        emit TransferToEvent(address(mockEventPod), address(mockToken), user1, transferAmount);

        fundingPod.transferToEvent(address(mockToken), user1, transferAmount);

        assertEq(fundingPod.getUserBalance(user1, address(mockToken)), depositAmount - transferAmount);
        assertEq(fundingPod.tokenBalances(address(mockToken)), depositAmount - transferAmount);
        assertEq(mockToken.balanceOf(address(mockEventPod)), transferAmount);
    }

    function testReceiveFromEventETH() public {
        uint256 depositAmount = 10 ether;
        uint256 transferAmount = 3 ether;
        uint256 returnAmount = 5 ether; // Return more than transferred (with rewards)

        // User deposits and transfers to event
        vm.prank(user1);
        fundingPod.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);

        vm.prank(address(mockEventPod));
        fundingPod.transferToEvent(ETH_ADDRESS, user1, transferAmount);

        // EventPod returns funds
        vm.deal(address(mockEventPod), returnAmount);
        vm.prank(address(mockEventPod));
        vm.expectEmit(true, true, true, true);
        emit ReceiveFromEvent(address(mockEventPod), ETH_ADDRESS, user1, returnAmount);

        fundingPod.receiveFromEvent{value: returnAmount}(ETH_ADDRESS, user1, returnAmount);

        uint256 expectedBalance = depositAmount - transferAmount + returnAmount;
        assertEq(fundingPod.getUserBalance(user1, ETH_ADDRESS), expectedBalance);
        assertEq(fundingPod.tokenBalances(ETH_ADDRESS), expectedBalance);
    }

    function testReceiveFromEventERC20() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 transferAmount = 300 * 10 ** 18;
        uint256 returnAmount = 500 * 10 ** 18; // Return more than transferred (with rewards)

        // User deposits and transfers to event
        vm.startPrank(user1);
        mockToken.approve(address(fundingPod), depositAmount);
        fundingPod.deposit(address(mockToken), depositAmount);
        vm.stopPrank();

        vm.prank(address(mockEventPod));
        fundingPod.transferToEvent(address(mockToken), user1, transferAmount);

        // EventPod returns funds - first transfer tokens to fundingPod
        mockToken.mint(address(mockEventPod), returnAmount);
        vm.startPrank(address(mockEventPod));
        mockToken.transfer(address(fundingPod), returnAmount);

        vm.expectEmit(true, true, true, true);
        emit ReceiveFromEvent(address(mockEventPod), address(mockToken), user1, returnAmount);

        fundingPod.receiveFromEvent(address(mockToken), user1, returnAmount);
        vm.stopPrank();

        uint256 expectedBalance = depositAmount - transferAmount + returnAmount;
        assertEq(fundingPod.getUserBalance(user1, address(mockToken)), expectedBalance);
        assertEq(fundingPod.tokenBalances(address(mockToken)), expectedBalance);
    }

    function testMultipleUsersDeposit() public {
        uint256 amount1 = 10 ether;
        uint256 amount2 = 20 ether;
        uint256 amount3 = 30 ether;

        vm.prank(user1);
        fundingPod.deposit{value: amount1}(ETH_ADDRESS, amount1);

        vm.prank(user2);
        fundingPod.deposit{value: amount2}(ETH_ADDRESS, amount2);

        vm.prank(user3);
        fundingPod.deposit{value: amount3}(ETH_ADDRESS, amount3);

        assertEq(fundingPod.getUserBalance(user1, ETH_ADDRESS), amount1);
        assertEq(fundingPod.getUserBalance(user2, ETH_ADDRESS), amount2);
        assertEq(fundingPod.getUserBalance(user3, ETH_ADDRESS), amount3);
        assertEq(fundingPod.tokenBalances(ETH_ADDRESS), amount1 + amount2 + amount3);
    }

    function testGetSupportTokens() public {
        address[] memory tokens = fundingPod.getSupportTokens();
        assertEq(tokens.length, 2);
    }

    function testGetTokenBalance() public {
        uint256 depositAmount = 10 ether;

        vm.prank(user1);
        fundingPod.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);

        assertEq(fundingPod.getTokenBalance(ETH_ADDRESS), depositAmount);
    }

    function testPauseAndUnpause() public {
        fundingPod.pause();

        vm.prank(user1);
        vm.expectRevert();
        fundingPod.deposit{value: 1 ether}(ETH_ADDRESS, 1 ether);

        fundingPod.unpause();

        vm.prank(user1);
        fundingPod.deposit{value: 1 ether}(ETH_ADDRESS, 1 ether);

        assertEq(fundingPod.getUserBalance(user1, ETH_ADDRESS), 1 ether);
    }

    // ==================== Error Cases ====================

    function testCannotDepositZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(FundingPod.InvalidAmount.selector);
        fundingPod.deposit{value: 0}(ETH_ADDRESS, 0);
    }

    function testCannotDepositUnsupportedToken() public {
        address unsupportedToken = address(0x555);

        vm.prank(user1);
        vm.expectRevert(FundingPod.TokenNotSupported.selector);
        fundingPod.deposit(unsupportedToken, 1000);
    }

    function testCannotWithdrawMoreThanBalance() public {
        uint256 depositAmount = 10 ether;

        vm.prank(user1);
        fundingPod.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);

        vm.prank(user1);
        vm.expectRevert(FundingPod.InsufficientUserBalance.selector);
        fundingPod.withdraw(ETH_ADDRESS, depositAmount + 1 ether);
    }

    function testCannotWithdrawZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(FundingPod.InvalidAmount.selector);
        fundingPod.withdraw(ETH_ADDRESS, 0);
    }

    function testOnlyEventPodCanTransferToEvent() public {
        vm.prank(user1);
        fundingPod.deposit{value: 10 ether}(ETH_ADDRESS, 10 ether);

        vm.prank(user2);
        vm.expectRevert(FundingPod.OnlyEventPod.selector);
        fundingPod.transferToEvent(ETH_ADDRESS, user1, 1 ether);
    }

    function testOnlyEventPodCanReceiveFromEvent() public {
        vm.prank(user1);
        vm.expectRevert(FundingPod.OnlyEventPod.selector);
        fundingPod.receiveFromEvent{value: 1 ether}(ETH_ADDRESS, user1, 1 ether);
    }

    function testOnlyFundingManagerCanAddSupportToken() public {
        address newToken = address(0x444);

        vm.prank(user1);
        vm.expectRevert(FundingPod.OnlyFundingManager.selector);
        fundingPod.addSupportToken(newToken);
    }

    function testOnlyFundingManagerCanRemoveSupportToken() public {
        vm.prank(user1);
        vm.expectRevert(FundingPod.OnlyFundingManager.selector);
        fundingPod.removeSupportToken(address(mockToken));
    }

    function testOnlyFundingManagerCanSetEventPod() public {
        address newEventPod = address(0x333);

        vm.prank(user1);
        vm.expectRevert(FundingPod.OnlyFundingManager.selector);
        fundingPod.setEventPod(newEventPod);
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        fundingPod.pause();
    }

    function testETHDepositValueMismatch() public {
        vm.prank(user1);
        vm.expectRevert(FundingPod.InvalidAmount.selector);
        fundingPod.deposit{value: 5 ether}(ETH_ADDRESS, 10 ether);
    }

    function testERC20DepositWithETHValue() public {
        vm.startPrank(user1);
        mockToken.approve(address(fundingPod), 1000 * 10 ** 18);

        vm.expectRevert(FundingPod.InvalidAmount.selector);
        fundingPod.deposit{value: 1 ether}(address(mockToken), 1000 * 10 ** 18);
        vm.stopPrank();
    }

    function testCannotTransferMoreThanUserBalance() public {
        uint256 depositAmount = 10 ether;

        vm.prank(user1);
        fundingPod.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);

        // Try to transfer more than user balance but less than total balance
        // First add more balance from another user
        vm.prank(user2);
        fundingPod.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);

        vm.prank(address(mockEventPod));
        vm.expectRevert(FundingPod.InsufficientUserBalance.selector);
        fundingPod.transferToEvent(ETH_ADDRESS, user1, depositAmount + 1 ether);
    }

    function testCannotAddZeroAddressToken() public {
        vm.expectRevert(FundingPod.InvalidAddress.selector);
        fundingManager.addSupportToken(address(fundingPod), address(0));
    }

    function testCannotSetZeroAddressEventPod() public {
        vm.expectRevert(FundingPod.InvalidAddress.selector);
        fundingManager.setEventPod(address(fundingPod), address(0));
    }

    // ==================== Integration Tests ====================

    function testCompleteDepositTransferReceiveWorkflow() public {
        uint256 depositAmount = 100 ether;
        uint256 betAmount = 30 ether;
        uint256 winAmount = 50 ether;

        // Step 1: User deposits
        vm.prank(user1);
        fundingPod.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);

        assertEq(fundingPod.getUserBalance(user1, ETH_ADDRESS), depositAmount);

        // Step 2: EventPod transfers to event (user places bet)
        vm.prank(address(mockEventPod));
        fundingPod.transferToEvent(ETH_ADDRESS, user1, betAmount);

        assertEq(fundingPod.getUserBalance(user1, ETH_ADDRESS), depositAmount - betAmount);

        // Step 3: EventPod returns funds (user wins)
        vm.deal(address(mockEventPod), winAmount);
        vm.prank(address(mockEventPod));
        fundingPod.receiveFromEvent{value: winAmount}(ETH_ADDRESS, user1, winAmount);

        uint256 finalBalance = depositAmount - betAmount + winAmount;
        assertEq(fundingPod.getUserBalance(user1, ETH_ADDRESS), finalBalance);

        // Step 4: User withdraws
        vm.prank(user1);
        fundingPod.withdraw(ETH_ADDRESS, finalBalance);

        assertEq(fundingPod.getUserBalance(user1, ETH_ADDRESS), 0);
    }

    function testMultipleTokensSupport() public {
        MockERC20 token2 = new MockERC20();
        token2.mint(user1, 10000 * 10 ** 18);

        // Add new token support
        fundingManager.addSupportToken(address(fundingPod), address(token2));

        // Deposit both tokens
        vm.startPrank(user1);

        mockToken.approve(address(fundingPod), 1000 * 10 ** 18);
        fundingPod.deposit(address(mockToken), 1000 * 10 ** 18);

        token2.approve(address(fundingPod), 2000 * 10 ** 18);
        fundingPod.deposit(address(token2), 2000 * 10 ** 18);

        vm.stopPrank();

        assertEq(fundingPod.getUserBalance(user1, address(mockToken)), 1000 * 10 ** 18);
        assertEq(fundingPod.getUserBalance(user1, address(token2)), 2000 * 10 ** 18);

        address[] memory supportedTokens = fundingPod.getSupportTokens();
        assertEq(supportedTokens.length, 3); // ETH + mockToken + token2
    }
}
