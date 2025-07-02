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

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        attacker = makeAddr("attacker");

        vm.startPrank(owner);
        governanceToken = new GovernanceToken("Token", "TKN", INITIAL_SUPPLY, owner);
        stakingContract = new FixedAPRStakingContract(address(governanceToken));
        vm.stopPrank();

        vm.startPrank(owner);
        governanceToken.transfer(user1, 10_000 ether);
        governanceToken.transfer(user2, 10_000 ether);
        governanceToken.transfer(user3, 10_000 ether);
        governanceToken.transfer(attacker, 1_000 ether);
        vm.stopPrank();

        vm.startPrank(owner);
        stakingContract.setBaseAPR(BASE_APR_365);
        governanceToken.approve(address(stakingContract), REWARD_POOL_AMOUNT);
        stakingContract.fundRewardPool(REWARD_POOL_AMOUNT);
        vm.stopPrank();
    }

    function testContructorInitialization() public view {
        assertEq(address(stakingContract.governanceToken()), address(governanceToken));
        assertEq(stakingContract.owner(), owner);
        assertEq(stakingContract.getStakePeriodsCount(), 5);

        (uint256 duration, bool active, uint256 apr) = stakingContract.getStakePeriod(0);
        assertEq(duration, 28 days);
        assertTrue(active);
        assertEq(apr, (BASE_APR_365 * 28) / 365);
    }
}
