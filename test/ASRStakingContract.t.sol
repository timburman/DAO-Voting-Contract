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
}
