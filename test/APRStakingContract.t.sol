// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GovernanceToken.sol";
import "../src/APRStakingContract.sol";

contract APRStakingContractTest is Test {
    GovernanceToken public governanceToken;
    APRStakingContract public stakingContract;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        governanceToken = new GovernanceToken("Token", "TKN", 1_000_000 ether, owner);
        stakingContract = new APRStakingContract(address(governanceToken), 1000, 7 days, owner);

        vm.startPrank(owner);
        governanceToken.mint(user1, 1000 ether);
        governanceToken.mint(user2, 10000 ether);
        governanceToken.mint(address(stakingContract), 100_000 ether);
        vm.stopPrank();
    }

    // -- Staking Tests --

    function testStakeIncreaseBalance() public {
        vm.startPrank(user1);
        governanceToken.approve(address(stakingContract), 500 ether);
        stakingContract.stake(500 ether);
        vm.stopPrank();

        assertEq(stakingContract.balanceOf(user1), 500 ether);
    }

    function testStakeEmitsEvent() public {
        vm.startPrank(user1);
        governanceToken.approve(address(stakingContract), 100 ether);
        vm.expectEmit(true, false, false, true);
        emit APRStakingContract.Staked(user1, 100 ether);
        stakingContract.stake(100 ether);
        vm.stopPrank();
    }

    function testStakeRevertsOnZero() public {
        vm.startPrank(user1);
        governanceToken.approve(address(stakingContract), 0);
        vm.expectRevert("Staking: Cannot stake 0 tokens");
        stakingContract.stake(0);
        vm.stopPrank();
    }

    // -- Rewards Logic --

    function testRewardActualWithCap() public {
        vm.startPrank(user1);
        governanceToken.approve(address(stakingContract), 100 ether);
        stakingContract.stake(100 ether);
        vm.stopPrank();

        vm.prank(owner);
        stakingContract.notifyRewardAmount(10 ether);

        skip(1 days);

        uint256 beforeClaim = governanceToken.balanceOf(user1);
        vm.prank(user1);
        stakingContract.claimRewards();

        uint256 afterClaim = governanceToken.balanceOf(user1);
        uint256 actualReward = afterClaim - beforeClaim;

        uint256 maxApr = 1000;
        uint256 totalStaked = 100 ether;
        uint256 expectedCappedRate = (totalStaked * maxApr) / (365 days) / 10000;

        uint256 expectedReward = expectedCappedRate * 1 days;

        uint256 delta = 1e14;

        assertApproxEqAbs(actualReward, expectedReward, delta);
        emit log_named_uint("Claimed Reward", actualReward);
    }

    function testRewardRateUsedWhenBelowAPRCap() public {
        uint256 stakeAmount = 100 ether;
        uint256 rewardAmount = 0.05 ether; // small enough to be below the APR cap

        // user1 stakes
        vm.startPrank(user1);
        governanceToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        // owner funds the rewards
        vm.prank(owner);
        stakingContract.notifyRewardAmount(rewardAmount);

        // rewardRate = rewardAmount / rewardDuration = 0.05 ether / 30 days
        uint256 rewardRate = rewardAmount / 30 days;

        // APR cap rate = (stakeAmount * aprBps) / (365 days * BPS_DIVISOR)
        uint256 aprCapRate = (stakeAmount * 10000) / (365 days * 10000); // = stakeAmount / 365 days

        // Ensure rewardRate is below the APR cap (for test validity)
        assertLt(rewardRate, aprCapRate);

        // Advance 1 day
        skip(1 days);

        // Claim rewards
        uint256 beforeClaim = governanceToken.balanceOf(user1);
        vm.prank(user1);
        stakingContract.claimRewards();
        uint256 afterClaim = governanceToken.balanceOf(user1);
        uint256 actualReward = afterClaim - beforeClaim;

        // expectedReward = rewardRate * time
        uint256 expectedReward = rewardRate * 1 days;

        // Assert within tolerance
        assertApproxEqAbs(actualReward, expectedReward, 1e12); // ~0.000001 token margin
    }
}
