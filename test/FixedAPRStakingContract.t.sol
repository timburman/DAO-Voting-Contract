// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/FixedAPRStakingContract.sol";
import "../src/GovernanceToken.sol";

contract FixedAPRStakingContractTest is Test {
    FixedAPRStakingContract public stakingContract;
    GovernanceToken public governanceToken;

    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public attacker;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 public constant BASE_APR_365 = 2000;
    uint256 public constant REWARD_POOL_AMOUNT = 100_000 ether;

    // Events to test
    event Staked(
        address indexed user,
        uint256 amount,
        uint256 aprInBps,
        uint256 stakeIndex,
        uint256 unlockTime,
        uint8 periodIndex,
        bool autoCompound
    );
    event RewardsClaimed(address indexed user, uint256 amount, uint256 stakeIndex, bool autoCompound);
    event Withdrawn(address indexed user, uint256 amount, uint256 stakeIndex, uint256 rewards);
    event BaseAPRUpdated(uint256 newBaseApr);
    event RewardPoolFunded(uint256 amount);
    event RewardsAddedToPool(address indexed user, uint256 amount, uint256 totalPoolAmount);
    event CompoundPoolFlushed(address indexed user, uint256 amount, uint256 newStakeIndex, uint8 periodIndex);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        attacker = makeAddr("attacker");

        vm.startPrank(owner);
        governanceToken = new GovernanceToken("Token", "TKN", INITIAL_SUPPLY, owner);
        stakingContract = new FixedAPRStakingContract(address(governanceToken), BASE_APR_365);
        vm.stopPrank();

        vm.startPrank(owner);
        governanceToken.transfer(user1, 10_000 ether);
        governanceToken.transfer(user2, 10_000 ether);
        governanceToken.transfer(user3, 10_000 ether);
        governanceToken.transfer(attacker, 1_000 ether);
        vm.stopPrank();

        vm.startPrank(owner);
        governanceToken.approve(address(stakingContract), REWARD_POOL_AMOUNT);
        stakingContract.fundRewardPool(REWARD_POOL_AMOUNT);
        vm.stopPrank();
    }

    // Basic Functionality Tests
    function testContructorInitialization() public view {
        assertEq(address(stakingContract.governanceToken()), address(governanceToken));
        assertEq(stakingContract.owner(), owner);
        assertEq(stakingContract.getStakePeriodsCount(), 5);

        (uint256 duration, bool active, uint256 apr) = stakingContract.getStakePeriod(0);
        assertEq(duration, 28);
        assertTrue(active);
        assertEq(apr, (BASE_APR_365 * 28) / 365);

        (uint256 duration365, bool active365, uint256 apr365) = stakingContract.getStakePeriod(4);
        assertEq(duration365, 365);
        assertTrue(active365);
        assertEq(apr365, BASE_APR_365);
    }

    function testStakeBasicFunctionality() public {
        uint256 stakeAmount = 1000 ether;
        uint8 periodIndex = 2;

        vm.startPrank(user1);
        governanceToken.approve(address(stakingContract), stakeAmount);

        vm.expectEmit(true, true, true, true);
        emit Staked(user1, stakeAmount, (BASE_APR_365 * 84) / 365, 0, block.timestamp + 84 days, periodIndex, false);
        stakingContract.stake(stakeAmount, periodIndex, false);
        vm.stopPrank();

        assertEq(stakingContract.getStakeCount(user1), 1);
        assertEq(stakingContract.getTotalStaked(user1), stakeAmount);
        assertEq(governanceToken.balanceOf(user1), 9_000 ether);

        FixedAPRStakingContract.StakeInfo memory info = stakingContract.getStakeInfo(user1, 0);
        assertEq(info.amount, stakeAmount);
        assertEq(info.periodIndex, periodIndex);
        assertTrue(info.active);
        assertFalse(info.autoCompound);
        assertFalse(info.canWithdraw);

        assertFalse(stakingContract.hasCompoundPool(user1));
    }

    function testStakeWithAutoCompound() public {
        uint256 stakeAmount = 500 ether;
        uint8 periodIndex = 1;

        vm.startPrank(user2);
        governanceToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, periodIndex, true);
        vm.stopPrank();

        FixedAPRStakingContract.StakeInfo memory info = stakingContract.getStakeInfo(user2, 0);
        assertTrue(info.autoCompound);
        assertEq(info.periodIndex, periodIndex);

        assertFalse(stakingContract.hasCompoundPool(user2));
    }

    function testMultipleStakesByUser() public {
        vm.startPrank(user1);
        governanceToken.approve(address(stakingContract), 5000 ether);

        stakingContract.stake(1000 ether, 0, false);
        stakingContract.stake(2000 ether, 2, true);
        stakingContract.stake(1500 ether, 4, false);
        vm.stopPrank();

        assertEq(stakingContract.getStakeCount(user1), 3);
        assertEq(stakingContract.getTotalStaked(user1), 4500 ether);

        FixedAPRStakingContract.StakeInfo memory stake1 = stakingContract.getStakeInfo(user1, 0);
        FixedAPRStakingContract.StakeInfo memory stake2 = stakingContract.getStakeInfo(user1, 1);
        FixedAPRStakingContract.StakeInfo memory stake3 = stakingContract.getStakeInfo(user1, 2);

        assertEq(stake1.periodIndex, 0);
        assertFalse(stake1.autoCompound);
        assertEq(stake1.amount, 1000 ether);

        assertEq(stake2.periodIndex, 2);
        assertTrue(stake2.autoCompound);
        assertEq(stake2.amount, 2000 ether);

        assertEq(stake3.periodIndex, 4);
        assertFalse(stake3.autoCompound);
        assertEq(stake3.amount, 1500 ether);

        skip(10 days);

        uint256 totalBalance = stakingContract.getTotalUserBalance(user1);
        assertGt(totalBalance, 4500 ether);
    }

    function testWithdrawAfterPeriodCompletion() public {
        uint256 stakeAmount = 1000 ether;
        uint8 periodIndex = 0;

        vm.startPrank(user1);
        governanceToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, periodIndex, false);
        vm.stopPrank();

        skip(29 days);

        FixedAPRStakingContract.StakeInfo memory info = stakingContract.getStakeInfo(user1, 0);
        assertTrue(info.canWithdraw);

        uint256 balanceBefore = governanceToken.balanceOf(user1);
        uint256 expectedRewards = stakingContract.getExpectedReward(user1, 0);

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(user1, stakeAmount, 0, expectedRewards);

        vm.prank(user1);
        stakingContract.withdraw(0);

        uint256 balanceAfter = governanceToken.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, stakeAmount + expectedRewards);

        FixedAPRStakingContract.StakeInfo memory finalInfo = stakingContract.getStakeInfo(user1, 0);
        assertFalse(finalInfo.active);
        assertFalse(finalInfo.canWithdraw);
    }

    // Compound Pool Functionality Tests

    function testClaimRewardsWithCompoundCreatesPool() public {
        uint256 stakeAmount = 1000 ether;
        uint8 periodIndex = 2;

        vm.startPrank(user1);
        governanceToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, periodIndex, true);
        vm.stopPrank();

        skip(30 days);

        assertFalse(stakingContract.hasCompoundPool(user1));
        assertEq(stakingContract.getCompoundPoolValue(user1), 0);

        uint256 expectedReward = stakingContract.getExpectedReward(user1, 0);
        assertGt(expectedReward, 0);

        uint256 balanceBefore = governanceToken.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit RewardsAddedToPool(user1, expectedReward, expectedReward);

        vm.prank(user1);
        stakingContract.claimRewards(0);

        uint256 balanceAfter = governanceToken.balanceOf(user1);

        assertEq(balanceBefore, balanceAfter);

        assertTrue(stakingContract.hasCompoundPool(user1));
        assertEq(stakingContract.getCompoundPoolValue(user1), expectedReward);

        (uint256 totalAmount, uint256 lastUpdateTime, uint8 preferredPeriod, bool hasActivePool) =
            stakingContract.getCompoundPoolInfo(user1);

        assertEq(totalAmount, expectedReward);
        assertEq(lastUpdateTime, block.timestamp);
        assertEq(preferredPeriod, periodIndex);
        assertTrue(hasActivePool);
    }

    function testClaimRewardsWithoutAutoCompoundTransfersTokens() public {
        uint256 stakeAmount = 1000 ether;
        uint8 periodIndex = 2;

        vm.startPrank(user1);
        governanceToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, periodIndex, false);
        vm.stopPrank();

        skip(30 days);

        uint256 expectedRewards = stakingContract.getExpectedReward(user1, 0);
        assertGt(expectedRewards, 0);

        uint256 balanceBefore = governanceToken.balanceOf(user1);

        vm.prank(user1);
        stakingContract.claimRewards(0);

        uint256 balanceAfter = governanceToken.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, expectedRewards);

        skip(15 days);
        uint256 newExpectedRewards = stakingContract.getExpectedReward(user1, 0);
        assertGt(newExpectedRewards, 0);

        assertFalse(stakingContract.hasCompoundPool(user1));
    }

    function testMultipleClaimsAccumulateInCompoundPool() public {
        uint256 stakeAmount = 2000 ether;
        uint8 periodIndex = 1;

        vm.startPrank(user1);
        governanceToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount, periodIndex, true);
        vm.stopPrank();

        skip(20 days);
        uint256 firstReward = stakingContract.getExpectedReward(user1, 0);

        vm.prank(user1);
        stakingContract.claimRewards(0);

        assertEq(stakingContract.getCompoundPoolValue(user1), firstReward);

        skip(15 days);
        uint256 secondReward = stakingContract.getExpectedReward(user1, 0);

        vm.prank(user1);
        stakingContract.claimRewards(0);

        uint256 totalPoolValue = stakingContract.getCompoundPoolValue(user1);
        assertApproxEqAbs(totalPoolValue, firstReward + secondReward, 1e15);
    }
}
