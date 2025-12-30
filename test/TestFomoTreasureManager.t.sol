// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@/token/allocation/FomoTreasureManager.sol";
import "@/interfaces/token/IFomoTreasureManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 10000000 * 10 ** 6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FomoTreasureManagerTest is Test {
    FomoTreasureManager public fomoManager;
    MockERC20 public mockToken;
    MockERC20 public rewardToken;

    address public owner = address(0x01);
    address public user1 = address(0x02);
    address public user2 = address(0x03);
    address public recipient = address(0x04);

    address public constant NATIVE_TOKEN_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    event Deposit(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount
    );

    event Withdraw(
        address indexed tokenAddress,
        address sender,
        address withdrawAddress,
        uint256 amount
    );

    function setUp() public {
        // Deploy mock tokens
        mockToken = new MockERC20();
        rewardToken = new MockERC20();

        // Deploy FomoTreasureManager with proxy
        FomoTreasureManager logic = new FomoTreasureManager();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(logic),
            owner,
            ""
        );

        fomoManager = FomoTreasureManager(payable(address(proxy)));

        // Initialize FomoTreasureManager
        fomoManager.initialize(owner, address(rewardToken), address(mockToken));

        // Setup user balances
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        mockToken.mint(user1, 100000 * 10 ** 6);
        mockToken.mint(user2, 100000 * 10 ** 6);

        // Approve tokens
        vm.prank(user1);
        mockToken.approve(address(fomoManager), type(uint256).max);
        vm.prank(user2);
        mockToken.approve(address(fomoManager), type(uint256).max);
    }

    function testInitialization() public {
        assertEq(fomoManager.rewardTokenAddress(), address(rewardToken), "Reward token address should be set correctly");
        assertEq(fomoManager.underlyingToken(), address(mockToken), "Underlying token address should be set correctly");
        assertEq(fomoManager.owner(), owner, "Owner should be set correctly");
        assertEq(fomoManager.NativeTokenAddress(), NATIVE_TOKEN_ADDRESS, "Native token address constant should be correct");
    }

    function testDepositNativeToken() public {
        uint256 depositAmount = 10 ether;
        uint256 contractBalanceBefore = address(fomoManager).balance;

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Deposit(NATIVE_TOKEN_ADDRESS, user1, depositAmount);
        bool success = fomoManager.deposit{value: depositAmount}();

        assertTrue(success, "Deposit should return true");
        assertEq(address(fomoManager).balance, contractBalanceBefore + depositAmount, "Contract native balance should increase");
        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), depositAmount, "FundingBalance should track deposit");
    }

    function testReceiveNativeToken() public {
        uint256 depositAmount = 5 ether;

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Deposit(NATIVE_TOKEN_ADDRESS, user1, depositAmount);
        (bool success, ) = address(fomoManager).call{value: depositAmount}("");

        assertTrue(success, "Direct transfer should succeed");
        assertEq(address(fomoManager).balance, depositAmount, "Contract should have received native token");
        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), depositAmount, "FundingBalance should track received amount");
    }

    function testDepositNativeTokenMultipleTimes() public {
        uint256 depositAmount1 = 5 ether;
        uint256 depositAmount2 = 3 ether;

        vm.prank(user1);
        fomoManager.deposit{value: depositAmount1}();

        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), depositAmount1, "First deposit should be tracked");

        vm.prank(user2);
        fomoManager.deposit{value: depositAmount2}();

        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), depositAmount1 + depositAmount2, "Multiple deposits should accumulate");
    }

    function testDepositErc20() public {
        uint256 depositAmount = 1000 * 10 ** 6;
        uint256 userBalanceBefore = mockToken.balanceOf(user1);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(fomoManager));

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Deposit(address(mockToken), user1, depositAmount);
        bool success = fomoManager.depositErc20(depositAmount);

        assertTrue(success, "ERC20 deposit should return true");
        assertEq(mockToken.balanceOf(user1), userBalanceBefore - depositAmount, "User balance should decrease");
        assertEq(mockToken.balanceOf(address(fomoManager)), contractBalanceBefore + depositAmount, "Contract balance should increase");
        assertEq(fomoManager.FundingBalance(address(mockToken)), depositAmount, "FundingBalance should track ERC20 deposit");
    }

    function testDepositErc20MultipleTimes() public {
        uint256 depositAmount1 = 1000 * 10 ** 6;
        uint256 depositAmount2 = 500 * 10 ** 6;

        vm.prank(user1);
        fomoManager.depositErc20(depositAmount1);

        assertEq(fomoManager.FundingBalance(address(mockToken)), depositAmount1, "First ERC20 deposit should be tracked");

        vm.prank(user2);
        fomoManager.depositErc20(depositAmount2);

        assertEq(fomoManager.FundingBalance(address(mockToken)), depositAmount1 + depositAmount2, "Multiple ERC20 deposits should accumulate");
    }

    function testWithdrawNativeToken() public {
        uint256 depositAmount = 10 ether;
        uint256 withdrawAmount = 3 ether;

        vm.prank(user1);
        fomoManager.deposit{value: depositAmount}();

        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(user2);
        vm.expectEmit(true, false, false, true);
        emit Withdraw(NATIVE_TOKEN_ADDRESS, user2, recipient, withdrawAmount);
        bool success = fomoManager.withdraw(payable(recipient), withdrawAmount);

        assertTrue(success, "Withdraw should return true");
        assertEq(recipient.balance, recipientBalanceBefore + withdrawAmount, "Recipient should receive native tokens");
        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), depositAmount - withdrawAmount, "FundingBalance should decrease");
    }

    function testWithdrawNativeTokenMultipleTimes() public {
        uint256 depositAmount = 10 ether;

        vm.prank(user1);
        fomoManager.deposit{value: depositAmount}();

        vm.prank(user1);
        fomoManager.withdraw(payable(recipient), 3 ether);

        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), 7 ether, "FundingBalance after first withdraw");

        vm.prank(user1);
        fomoManager.withdraw(payable(recipient), 2 ether);

        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), 5 ether, "FundingBalance after second withdraw");
    }

    function testWithdrawNativeTokenRevertsOnInsufficientBalance() public {
        uint256 depositAmount = 5 ether;
        uint256 withdrawAmount = 6 ether;

        vm.prank(user1);
        fomoManager.deposit{value: depositAmount}();

        vm.prank(user1);
        vm.expectRevert("FomoTreasureManager withdraw: insufficient native token balance in contract");
        fomoManager.withdraw(payable(recipient), withdrawAmount);
    }

    function testWithdrawErc20() public {
        uint256 depositAmount = 1000 * 10 ** 6;
        uint256 withdrawAmount = 300 * 10 ** 6;

        // First deposit reward tokens to contract
        rewardToken.transfer(address(fomoManager), depositAmount);

        vm.prank(user1);
        fomoManager.depositErc20(depositAmount);

        uint256 recipientBalanceBefore = rewardToken.balanceOf(recipient);

        vm.prank(user2);
        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(mockToken), user2, recipient, withdrawAmount);
        bool success = fomoManager.withdrawErc20(recipient, withdrawAmount);

        assertTrue(success, "ERC20 withdraw should return true");
        assertEq(rewardToken.balanceOf(recipient), recipientBalanceBefore + withdrawAmount, "Recipient should receive reward tokens");
        assertEq(fomoManager.FundingBalance(address(mockToken)), depositAmount - withdrawAmount, "FundingBalance should decrease");
    }

    function testWithdrawErc20RevertsOnInsufficientBalance() public {
        uint256 depositAmount = 1000 * 10 ** 6;
        uint256 withdrawAmount = 1500 * 10 ** 6;

        rewardToken.transfer(address(fomoManager), depositAmount);

        vm.prank(user1);
        fomoManager.depositErc20(depositAmount);

        vm.prank(user1);
        vm.expectRevert("FomoTreasureManager: withdraw erc20 amount more token balance in this contracts");
        fomoManager.withdrawErc20(recipient, withdrawAmount);
    }

    function testMixedDepositAndWithdraw() public {
        uint256 nativeDeposit = 5 ether;
        uint256 erc20Deposit = 1000 * 10 ** 6;

        // Deposit native token
        vm.prank(user1);
        fomoManager.deposit{value: nativeDeposit}();

        // Deposit ERC20
        vm.prank(user1);
        fomoManager.depositErc20(erc20Deposit);

        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), nativeDeposit, "Native token balance should be tracked");
        assertEq(fomoManager.FundingBalance(address(mockToken)), erc20Deposit, "ERC20 balance should be tracked");

        // Withdraw native
        vm.prank(user1);
        fomoManager.withdraw(payable(recipient), 2 ether);

        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), 3 ether, "Native balance should decrease after withdraw");
        assertEq(fomoManager.FundingBalance(address(mockToken)), erc20Deposit, "ERC20 balance should remain unchanged");
    }

    function testDepositWhenPaused() public {
        vm.prank(owner);
        fomoManager.pause();

        vm.prank(user1);
        vm.expectRevert();
        fomoManager.deposit{value: 1 ether}();

        vm.prank(user1);
        vm.expectRevert();
        fomoManager.depositErc20(1000 * 10 ** 6);
    }

    function testWithdrawWhenPaused() public {
        // Deposit first
        vm.prank(user1);
        fomoManager.deposit{value: 5 ether}();

        vm.prank(user1);
        fomoManager.depositErc20(1000 * 10 ** 6);

        // Pause contract
        vm.prank(owner);
        fomoManager.pause();

        // Try to withdraw
        vm.prank(user1);
        vm.expectRevert();
        fomoManager.withdraw(payable(recipient), 1 ether);

        vm.prank(user1);
        vm.expectRevert();
        fomoManager.withdrawErc20(recipient, 100 * 10 ** 6);
    }

    function testUnpauseAndContinueOperations() public {
        vm.prank(owner);
        fomoManager.pause();

        vm.prank(owner);
        fomoManager.unpause();

        // Should work after unpause
        vm.prank(user1);
        bool success = fomoManager.deposit{value: 1 ether}();
        assertTrue(success, "Deposit should work after unpause");
    }

    function testFundingBalanceTracksCorrectly() public {
        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), 0, "Initial native balance should be 0");
        assertEq(fomoManager.FundingBalance(address(mockToken)), 0, "Initial ERC20 balance should be 0");

        vm.prank(user1);
        fomoManager.deposit{value: 10 ether}();

        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), 10 ether, "Native balance should be 10 ether");

        vm.prank(user1);
        fomoManager.depositErc20(5000 * 10 ** 6);

        assertEq(fomoManager.FundingBalance(address(mockToken)), 5000 * 10 ** 6, "ERC20 balance should be 5000 USDT");
    }

    function testMultipleUsersDepositsAndWithdraws() public {
        // User1 deposits
        vm.prank(user1);
        fomoManager.deposit{value: 10 ether}();

        // User2 deposits
        vm.prank(user2);
        fomoManager.deposit{value: 5 ether}();

        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), 15 ether, "Total deposits should be 15 ether");

        // User1 withdraws
        vm.prank(user1);
        fomoManager.withdraw(payable(user1), 3 ether);

        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), 12 ether, "Balance after user1 withdraw");

        // User2 withdraws
        vm.prank(user2);
        fomoManager.withdraw(payable(user2), 2 ether);

        assertEq(fomoManager.FundingBalance(NATIVE_TOKEN_ADDRESS), 10 ether, "Balance after user2 withdraw");
    }

    function testConstants() public view {
        assertEq(fomoManager.NativeTokenAddress(), NATIVE_TOKEN_ADDRESS, "Native token address constant should match");
    }

    function testOwnershipFunctions() public {
        assertEq(fomoManager.owner(), owner, "Owner should be initial owner");

        vm.prank(owner);
        fomoManager.transferOwnership(user1);

        assertEq(fomoManager.owner(), user1, "Owner should be transferred to user1");
    }
}
