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

    function testTokenName() public view {
        assertEq(token.name(), "Token");
    }

    function testTransfer(address tempWallet) public {
        vm.prank(owner);
        token.transfer(tempWallet, 1000);
        assertEq(token.balanceOf(tempWallet), 1000);
    }

    modifier receiveTokens(address tempWallet) {
        vm.prank(owner);
        token.transfer(tempWallet, 1000);
        _;
    }

    function testStake(address tempWallet) public receiveTokens(tempWallet) {
        vm.startPrank(tempWallet);
        token.approve(address(stakingContract), 600);
        stakingContract.stake(600);
        vm.stopPrank();
        assertEq(stakingContract.stakedBalance(tempWallet), 600);
    }

    function testStakeWithoutApproval(
        address tempWallet
    ) public receiveTokens(tempWallet) {
        vm.prank(tempWallet);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "ERC20InsufficientAllowance(address,uint256,uint256)"
                    )
                ),
                address(stakingContract),
                0,
                500
            )
        );
        stakingContract.stake(500);
    }

    function testStakewithoutBalance(address tempWallet) public {
        vm.prank(tempWallet);
        vm.expectRevert("Insufficient Balance");
        stakingContract.stake(1000);
    }

    function testUnstake(address tempWallet) public receiveTokens(tempWallet) {
        vm.startPrank(tempWallet);
        token.approve(address(stakingContract), 600);
        stakingContract.stake(600);

        stakingContract.initiateUnstaking(400);
        vm.stopPrank();

        (uint256 amount, uint256 unlockTime) = stakingContract.unstakingRequest(
            tempWallet
        );

        assertEq(amount, 400);
        assertGe(unlockTime, block.timestamp);
    }
}
