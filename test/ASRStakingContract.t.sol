// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/ASRStakingContract.sol";
import "../src/GovernanceToken.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract ASRStakingContractTest is Test {
    ASRStakingContract public staking;
    ASRStakingContract public stakingImpl;
    GovernanceToken public token;
    ProxyAdmin public proxyAdmin;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    uint256 public constant INITIAL_BALANCE = 100000 ether;
    uint256 public constant COOLDOWN_PERIOD = 7 days;

    event Staked(address indexed user, uint256 amount, uint256 newTotalStaked, uint256 newUserBalance);
    event UnstakeRequested(
        address indexed user, uint256 amount, uint256 requestTime, uint256 requestIndex, uint256 claimableAt
    );
    event UnstakeClaimed(address indexed user, uint256 amount, uint256 originalRequestIndex);
    event BatchUnstakeClaimed(address indexed user, uint256 totalAmount, uint256 requestCount);

    function setUp() public {
        token = new GovernanceToken("Governance Token", "GOV", INITIAL_BALANCE, owner);
        proxyAdmin = new ProxyAdmin(owner);
        stakingImpl = new ASRStakingContract();

        bytes memory initData =
            abi.encodeWithSelector(ASRStakingContract.initialize.selector, address(token), COOLDOWN_PERIOD, owner);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(stakingImpl), address(proxyAdmin), initData);
        staking = ASRStakingContract(address(proxy));

        vm.startPrank(owner);
        token.transfer(user1, 10000 ether);
        token.transfer(user2, 20000 ether);
        token.transfer(user3, 30000 ether);
        vm.stopPrank();

        vm.prank(user1);
        token.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);
        vm.prank(user3);
        token.approve(address(staking), type(uint256).max);
    }

    function test_initialize_success() public view {
        assertEq(address(staking.stakingToken()), address(token));
        assertEq(staking.owner(), owner);
        assertEq(staking.cooldownPeriod(), COOLDOWN_PERIOD);
        assertEq(staking.minimumStakeAmount(), 1 ether);
        assertEq(staking.minimumUnstakeAmount(), 1 ether);
        assertFalse(staking.emergencyMode());
    }

    function testInitializeInvalidToken() public {
        ASRStakingContract newImpl = new ASRStakingContract();

        vm.expectRevert("Invalid Token");
        newImpl.initialize(address(0), COOLDOWN_PERIOD, owner);
    }

    function testInitializeInvalidOwner() public {
        ASRStakingContract newImpl = new ASRStakingContract();

        vm.expectRevert("Invalid owner");
        newImpl.initialize(address(token), COOLDOWN_PERIOD, address(0));
    }

    function testInitializeInvallidCooldown() public {
        ASRStakingContract newImpl = new ASRStakingContract();

        vm.expectRevert("Cooldown out of range");
        newImpl.initialize(address(token), 6 days, owner);

        vm.expectRevert("Cooldown out of range");
        newImpl.initialize(address(token), 31 days, owner);
    }

    // -- Staking Tests --
    function testStakeSuccess() public {
        uint256 stakeAmount = 1000 ether;

        vm.expectEmit(true, true, true, true);
        emit Staked(user1, stakeAmount, stakeAmount, stakeAmount);

        vm.prank(user1);
        staking.stake(stakeAmount);

        assertEq(staking.getStakedAmount(user1), stakeAmount);
        assertEq(staking.getTotalStaked(), stakeAmount);
        assertEq(staking.getVotingPower(user1), stakeAmount);
        assertEq(token.balanceOf(user1), 9000 ether);
    }

    function testStakeMultipleUsers() public {
        uint256 stakeAmount1 = 1000 ether;
        uint256 stakeAmount2 = 2000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount1);

        vm.prank(user2);
        staking.stake(stakeAmount2);

        assertEq(staking.getStakedAmount(user1), stakeAmount1);
        assertEq(staking.getStakedAmount(user2), stakeAmount2);
        assertEq(staking.getTotalStaked(), stakeAmount1 + stakeAmount2);
    }

    function testStakeBelowMinimum() public {
        vm.prank(user1);

        vm.expectRevert("Amount below minimum");
        staking.stake(0.5 ether);
    }

    function testStakeInsufficientBalance() public {
        uint256 stakeAmount = 100000 ether; // More than user1's balance

        vm.prank(user1);
        vm.expectRevert("Insufficient token balance");
        staking.stake(stakeAmount);
    }

    function testStakeInsufficientAllowance() public {
        address newUser = address(0x707);

        vm.prank(owner);
        token.transfer(newUser, 1000 ether);

        vm.prank(newUser);
        vm.expectRevert("Insufficient allowance");
        staking.stake(1000 ether);
    }

    // -- Unstake Tests --

    function testUnstakeSuccess() public {
        uint256 stakeAmount = 1000 ether;
        uint256 unstakeAmount = 500 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.expectEmit(true, true, true, true);
        emit UnstakeRequested(user1, unstakeAmount, block.timestamp, 0, block.timestamp + COOLDOWN_PERIOD);

        vm.prank(user1);
        staking.unstake(unstakeAmount);

        assertEq(staking.getStakedAmount(user1), stakeAmount - unstakeAmount);
        assertEq(staking.getTotalStaked(), stakeAmount - unstakeAmount);
        assertEq(staking.getPendingUnstakeCount(user1), 1);
        assertEq(staking.getTotalPendingUnstake(user1), unstakeAmount);
    }

    function testUnstakeMultipleRequests() public {
        uint256 stakeAmount = 3000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(500 ether);

        vm.prank(user1);
        staking.unstake(700 ether);

        vm.prank(user1);
        staking.unstake(800 ether);

        assertEq(staking.getPendingUnstakeCount(user1), 3);
        assertEq(staking.getTotalPendingUnstake(user1), 2000 ether);
        assertEq(staking.getStakedAmount(user1), 1000 ether);
    }

    function testUnstakeMaxRequestsReached() public {
        uint256 stakeAmount = 3000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(500 ether);
        vm.prank(user1);
        staking.unstake(500 ether);
        vm.prank(user1);
        staking.unstake(500 ether);

        vm.prank(user1);
        vm.expectRevert("Max unstake requests reached");
        staking.unstake(500 ether);
    }

    function testUnstakeInsufficientStaked() public {
        vm.prank(user1);
        vm.expectRevert("Insufficient staked");
        staking.unstake(100 ether);
    }

    function unstakeBelowMinimum() public {
        vm.prank(user1);
        staking.stake(2 ether);

        vm.prank(user1);
        vm.expectRevert("Amount below minimum");
        staking.unstake(0.5 ether);
    }

    // -- Claim Tests --

    function testClaimUnstakeBeforeCooldownFails() public {
        uint256 stakeAmount = 1000 ether;
        uint256 unstakeAmount = 500 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(unstakeAmount);

        vm.prank(user1);
        vm.expectRevert("Cooldown not passed");
        staking.claimUnstake(0);
    }

    function testClaimUnstakeAfterCooldownSuccess() public {
        uint256 stakeAmount = 1000 ether;
        uint256 unstakeAmount = 500 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(unstakeAmount);

        skip(COOLDOWN_PERIOD + 1 seconds);

        uint256 balanceBefore = token.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit UnstakeClaimed(user1, unstakeAmount, 0);

        vm.prank(user1);
        staking.claimUnstake(0);

        assertEq(token.balanceOf(user1), balanceBefore + unstakeAmount);
        assertEq(staking.getPendingUnstakeCount(user1), 0);
        assertEq(staking.getTotalPendingUnstake(user1), 0);
    }

    function testClaimUnstakeInvalidRequest() public {
        vm.prank(user1);
        vm.expectRevert("Invalid request");
        staking.claimUnstake(1);
    }

    function testclaimAllReadySuccess() public {
        uint stakeAmount = 3000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(1000 ether);

        vm.prank(user1);
        staking.unstake(1000 ether);

        vm.prank(user1);
        staking.unstake(1000 ether);

        skip(COOLDOWN_PERIOD + 1 seconds);

        uint256 balanceBefore = token.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit BatchUnstakeClaimed(user1, 3000 ether, 3);

        vm.prank(user1);
        staking.claimAllReady();

        assertEq(token.balanceOf(user1), balanceBefore + 3000 ether);
        assertEq(staking.getPendingUnstakeCount(user1), 0);
    }

    function testClaimAllReadyPartial() public {
        uint stakeAmount = 3000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(1000 ether);

        skip(4 days);

        vm.prank(user1);
        staking.unstake(500 ether);

        skip(4 days);

        uint balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        staking.claimAllReady();

        assertEq(token.balanceOf(user1), balanceBefore + 1000 ether);
        assertEq(staking.getPendingUnstakeCount(user1), 1);
        assertEq(staking.getTotalPendingUnstake(user1), 500 ether);
    }

    function testClaimAllReadyNoRequests() public {
        vm.prank(user1);
        vm.expectRevert("No unstake requests");
        staking.claimAllReady();
    }

}
