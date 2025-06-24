// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StakingContract.sol";
import "../src/GovernanceToken.sol";

contract TestStakingContract is Test {
    StakingContract public stakingContract;
    GovernanceToken public token;
    address public owner;

    function setUp() public {
        owner = makeAddr("owner");
        vm.startPrank(owner);
        token = new GovernanceToken("Token", "TKN", 100000, owner);
        stakingContract = new StakingContract(address(token), owner);
        vm.stopPrank();
    }

    // Helper Functions
    function makeStake(address tempWallet, uint256 amount) internal {
        vm.startPrank(tempWallet);
        token.approve(address(stakingContract), amount);
        stakingContract.stake(amount);
        vm.stopPrank();
    }

    function receiveTokens(address tempWallet) internal {
        vm.prank(owner);
        token.transfer(tempWallet, 1000);
    }

    // End Helper Functions

    function testTokenName() public view {
        assertEq(token.name(), "Token");
    }

    function testTransfer(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        vm.prank(owner);
        token.transfer(tempWallet, 1000);
        assertEq(token.balanceOf(tempWallet), 1000);
    }

    function testStake(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        receiveTokens(tempWallet);

        makeStake(tempWallet, 600);
        assertEq(stakingContract.stakedBalance(tempWallet), 600);
    }

    function testStakeWithoutApproval(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        receiveTokens(tempWallet);

        vm.prank(tempWallet);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)")),
                address(stakingContract),
                0,
                500
            )
        );
        stakingContract.stake(500);
    }

    function testStakewithoutBalance(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        vm.startPrank(tempWallet);
        token.approve(address(stakingContract), 500);
        vm.expectRevert("Insufficient Balance");
        stakingContract.stake(500);
        vm.stopPrank();
    }

    function testCannotStakeZero(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        receiveTokens(tempWallet);

        vm.startPrank(tempWallet);
        token.approve(address(stakingContract), 0);
        vm.expectRevert("Cannot stake zero Tokens");
        stakingContract.stake(0);
        vm.stopPrank();
    }

    function testUnstake(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        receiveTokens(tempWallet);
        makeStake(tempWallet, 600);

        vm.startPrank(tempWallet);

        stakingContract.initiateUnstaking(400);
        vm.stopPrank();

        (uint256 amount, uint256 unlockTime) = stakingContract.unstakingRequest(tempWallet);

        assertEq(amount, 400);
        assertGe(unlockTime, block.timestamp);
    }

    function testUnstakeAndWithdraw(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        receiveTokens(tempWallet);
        makeStake(tempWallet, 600);

        vm.startPrank(tempWallet);

        stakingContract.initiateUnstaking(400);
        vm.warp(block.timestamp + 7 days);
        stakingContract.withdraw();
        vm.stopPrank();
        (uint256 amount, uint256 unlockTime) = stakingContract.unstakingRequest(tempWallet);
        assertEq(amount, 0);
        assertEq(unlockTime, 0);
    }

    function testCannotUnstakeZero(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        receiveTokens(tempWallet);
        makeStake(tempWallet, 500);

        vm.prank(tempWallet);
        vm.expectRevert("Cannot Unstake zero tokens");
        stakingContract.initiateUnstaking(0);
    }

    function testUnstakeMoreThanStaked(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        receiveTokens(tempWallet);
        makeStake(tempWallet, 500);

        vm.prank(tempWallet);
        vm.expectRevert("Insufficient staked balance");
        stakingContract.initiateUnstaking(1000);
    }

    function testCannotUnstakeTwice(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        receiveTokens(tempWallet);
        makeStake(tempWallet, 500);

        vm.startPrank(tempWallet);
        stakingContract.initiateUnstaking(200);

        vm.expectRevert("Unstake Already in Process");
        stakingContract.initiateUnstaking(300);
        vm.stopPrank();
    }

    function testCannotWithdrawEarly(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        receiveTokens(tempWallet);
        makeStake(tempWallet, 500);

        vm.startPrank(tempWallet);
        stakingContract.initiateUnstaking(300);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert("Unstake period not over");
        stakingContract.withdraw();
    }

    function testCannotWithdrawWithoutUnstake(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);

        vm.prank(tempWallet);
        vm.expectRevert("No Unstake Request Found");
        stakingContract.withdraw();
    }

    function testTotalStakeUpdatesCorrectly(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        receiveTokens(tempWallet);
        makeStake(tempWallet, 500);
        uint256 totalStakedBefore = stakingContract.totalStaked();

        vm.startPrank(tempWallet);
        stakingContract.initiateUnstaking(200);
        vm.stopPrank();
        assertEq(stakingContract.totalStaked(), totalStakedBefore - 200);
    }
}
