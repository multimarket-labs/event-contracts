// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@/token/allocation/DaoRewardManager.sol";
import "@/interfaces/token/IDaoRewardManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// forge test --match-contract DaoRewardManagerTest -vvv
// Mock ERC20 Token for testing
contract MockRewardToken is ERC20 {
    constructor() ERC20("Mock Reward Token", "MRT") {
        _mint(msg.sender, 10000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DaoRewardManagerTest is Test {
    DaoRewardManager public daoRewardManager;
    MockRewardToken public mockToken;

    address public owner = address(0x01);
    address public user1 = address(0x02);
    address public user2 = address(0x03);
    address public caller = address(0x04);

    function setUp() public {
        // Deploy mock token
        mockToken = new MockRewardToken();

        // Deploy DaoRewardManager with proxy
        DaoRewardManager logic = new DaoRewardManager();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(logic),
            owner,
            ""
        );

        daoRewardManager = DaoRewardManager(payable(address(proxy)));

        // Initialize DaoRewardManager
        daoRewardManager.initialize(owner, address(mockToken), caller, caller);

        // Transfer tokens to DaoRewardManager
        mockToken.transfer(address(daoRewardManager), 1000000 * 10 ** 18);
    }

    function testInitialization() public {
        assertEq(daoRewardManager.rewardTokenAddress(), address(mockToken), "Reward token address should be mockToken");
        assertEq(daoRewardManager.owner(), owner, "Owner should be set correctly");
    }

    function testWithdrawSuccess() public {
        uint256 withdrawAmount = 1000 * 10 ** 18;
        uint256 userBalanceBefore = mockToken.balanceOf(user1);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(daoRewardManager));

        vm.prank(caller);
        daoRewardManager.withdraw(user1, withdrawAmount);

        assertEq(mockToken.balanceOf(user1), userBalanceBefore + withdrawAmount, "User1 balance should increase by withdraw amount");
        assertEq(mockToken.balanceOf(address(daoRewardManager)), contractBalanceBefore - withdrawAmount, "Contract balance should decrease by withdraw amount");
    }

    function testWithdrawMultipleTimes() public {
        uint256 withdrawAmount1 = 1000 * 10 ** 18;
        uint256 withdrawAmount2 = 500 * 10 ** 18;

        vm.prank(caller);
        daoRewardManager.withdraw(user1, withdrawAmount1);

        assertEq(mockToken.balanceOf(user1), withdrawAmount1, "User1 balance should be withdraw amount after first withdraw");

        vm.prank(caller);
        daoRewardManager.withdraw(user1, withdrawAmount2);

        assertEq(mockToken.balanceOf(user1), withdrawAmount1 + withdrawAmount2, "User1 balance should be sum of both withdraws");
    }

    function testWithdrawToDifferentRecipients() public {
        uint256 withdrawAmount = 1000 * 10 ** 18;

        vm.prank(caller);
        daoRewardManager.withdraw(user1, withdrawAmount);

        vm.prank(caller);
        daoRewardManager.withdraw(user2, withdrawAmount);

        assertEq(mockToken.balanceOf(user1), withdrawAmount, "User1 should have withdraw amount");
        assertEq(mockToken.balanceOf(user2), withdrawAmount, "User2 should have withdraw amount");
    }

    function testWithdrawRevertsWhenAmountExceedsBalance() public {
        uint256 contractBalance = mockToken.balanceOf(address(daoRewardManager));
        uint256 excessiveAmount = contractBalance + 1;

        vm.prank(caller);
        vm.expectRevert("DaoRewardManager: withdraw amount more token balance in this contracts");
        daoRewardManager.withdraw(user1, excessiveAmount);
    }

    function testWithdrawEntireBalance() public {
        uint256 contractBalance = mockToken.balanceOf(address(daoRewardManager));

        vm.prank(caller);
        daoRewardManager.withdraw(user1, contractBalance);

        assertEq(mockToken.balanceOf(user1), contractBalance, "User1 should receive entire contract balance");
        assertEq(mockToken.balanceOf(address(daoRewardManager)), 0, "Contract balance should be 0");
    }

    function testWithdrawZeroAmount() public {
        uint256 userBalanceBefore = mockToken.balanceOf(user1);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(daoRewardManager));

        vm.prank(caller);
        daoRewardManager.withdraw(user1, 0);

        assertEq(mockToken.balanceOf(user1), userBalanceBefore, "User1 balance should not change with zero withdraw");
        assertEq(mockToken.balanceOf(address(daoRewardManager)), contractBalanceBefore, "Contract balance should not change with zero withdraw");
    }

    function testContractCanReceiveEther() public {
        uint256 sendAmount = 1 ether;
        
        vm.deal(user1, 10 ether);
        
        vm.prank(user1);
        (bool success, ) = address(daoRewardManager).call{value: sendAmount}("");
        
        assertTrue(success, "Contract should accept ether");
        assertEq(address(daoRewardManager).balance, sendAmount, "Contract should have received ether");
    }

    function testTokenBalanceReflectsCorrectAmount() public {
        uint256 expectedBalance = mockToken.balanceOf(address(daoRewardManager));
        
        // Add more tokens
        mockToken.transfer(address(daoRewardManager), 5000 * 10 ** 18);
        
        uint256 newExpectedBalance = expectedBalance + 5000 * 10 ** 18;
        assertEq(mockToken.balanceOf(address(daoRewardManager)), newExpectedBalance, "Contract balance should reflect new tokens");
    }

    function testMultipleWithdrawsDepletingBalance() public {
        uint256 initialBalance = mockToken.balanceOf(address(daoRewardManager));
        uint256 withdrawAmount = initialBalance / 4;

        for (uint256 i = 0; i < 4; i++) {
            vm.prank(caller);
            daoRewardManager.withdraw(user1, withdrawAmount);
        }

        assertEq(mockToken.balanceOf(address(daoRewardManager)), 0, "Contract should have 0 balance after depleting withdraws");
        assertEq(mockToken.balanceOf(user1), initialBalance, "User1 should have received entire initial balance");
    }

    function testWithdrawAfterReceivingMoreTokens() public {
        uint256 withdrawAmount1 = 1000 * 10 ** 18;
        
        vm.prank(caller);
        daoRewardManager.withdraw(user1, withdrawAmount1);

        // Add more tokens to contract
        mockToken.transfer(address(daoRewardManager), 5000 * 10 ** 18);

        uint256 withdrawAmount2 = 3000 * 10 ** 18;
        vm.prank(caller);
        daoRewardManager.withdraw(user2, withdrawAmount2);

        assertEq(mockToken.balanceOf(user1), withdrawAmount1, "User1 should have first withdraw amount");
        assertEq(mockToken.balanceOf(user2), withdrawAmount2, "User2 should have second withdraw amount");
    }

    function testUnauthorizedCallerCannotWithdraw() public {
        uint256 withdrawAmount = 1000 * 10 ** 18;

        // Test that non-authorized address cannot call withdraw
        address randomCaller = address(0x999);
        
        vm.prank(randomCaller);
        vm.expectRevert("DaoRewardManager: caller is not authorized");
        daoRewardManager.withdraw(user1, withdrawAmount);
    }

    function testWithdrawToContractAddress() public {
        uint256 withdrawAmount = 1000 * 10 ** 18;
        address contractRecipient = address(new MockRewardToken());

        vm.prank(caller);
        daoRewardManager.withdraw(contractRecipient, withdrawAmount);

        assertEq(mockToken.balanceOf(contractRecipient), withdrawAmount, "Contract recipient should receive tokens");
    }

    function testRewardTokenAddressIsSet() public view {
        assertEq(daoRewardManager.rewardTokenAddress(), address(mockToken), "Reward token address should be set correctly");
    }

    function testOwnershipIsSet() public view {
        assertEq(daoRewardManager.owner(), owner, "Owner should be set correctly during initialization");
    }
}
