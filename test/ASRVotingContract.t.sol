// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ASRStakingContract.sol";
import "../src/ASRVotingContract.sol";
import "../src/GovernanceToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ASRVotingContractTest is Test {
    ASRVotingContract public votingContract;
    ASRStakingContract public stakingContract;
    GovernanceToken public stakingToken;
    ERC1967Proxy stakingProxy;
    ERC1967Proxy votingProxy;

    address public owner = makeAddr("owner");
    address public admin1 = makeAddr("admin1");
    address public admin2 = makeAddr("admin2");
    address public proposer1 = makeAddr("proposer1");
    address public proposer2 = makeAddr("proposer1");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public safeAddress = makeAddr("safeAddress");

    uint256 public constant INITIAL_SUPPLY = 10_000_000 ether;
    uint256 public constant QUARTER_DURATION = 90 days;

    function setUp() public {
        stakingToken = new GovernanceToken("Staking token", "TKN", INITIAL_SUPPLY, owner);

        stakingContract = new ASRStakingContract();
        votingContract = new ASRVotingContract();

        vm.startPrank(owner);

        stakingProxy = new ERC1967Proxy(
            address(stakingContract),
            abi.encodeWithSelector(ASRStakingContract.initialize.selector, address(stakingToken), 7 days, owner)
        );

        votingProxy = new ERC1967Proxy(
            address(votingContract),
            abi.encodeWithSelector(
                ASRVotingContract.initialize.selector, address(stakingProxy), proposer1, address(stakingToken), owner
            )
        );

        stakingContract = ASRStakingContract(address(stakingProxy));
        votingContract = ASRVotingContract(address(votingProxy));

        stakingContract.setVotingContract(address(votingContract));

        stakingToken.transfer(user1, 1000 ether);
        stakingToken.transfer(user2, 2000 ether);

        vm.stopPrank();

        vm.prank(user1);
        stakingToken.approve(address(stakingContract), type(uint256).max);

        vm.prank(user2);
        stakingToken.approve(address(stakingContract), type(uint256).max);

        vm.prank(owner);
        stakingToken.approve(address(votingContract), type(uint256).max);
    }

    // -- 1. SETUP & INITIALIZATION TESTS --
    function testInitialize() public {
        // Deploy fresh contract
        ASRVotingContract newContract = new ASRVotingContract();

        vm.prank(owner);
        newContract.initialize(address(stakingContract), proposer1, address(stakingToken), owner);

        assertEq(address(newContract.stakingContract()), address(stakingContract));
        assertEq(newContract.owner(), owner);
        assertEq(newContract.proposalCounter(), 0);
        assertEq(newContract.activeProposalCount(), 0);
        assertEq(newContract.currentQuarter(), 0);
        assertFalse(newContract.proposalCreationEnabled());
    }

    function testInitializeWithZeroAddress() public {
        ASRVotingContract newContract = new ASRVotingContract();

        vm.startPrank(owner);

        vm.expectRevert("ASRVotingContract: Staking contract address cannot be zero");
        newContract.initialize(address(0), proposer1, address(stakingToken), owner);

        vm.expectRevert("ASRVotingContract: Owner address cannot be zero");
        newContract.initialize(address(stakingContract), proposer1, address(stakingToken), address(0));

        vm.stopPrank();
    }

    function testInitializeOnlyOne() public {
        vm.startPrank(owner);

        vm.expectRevert("InvalidInitialization()");
        votingContract.initialize(address(stakingContract), proposer1, address(stakingToken), owner);

        vm.stopPrank();
    }

    function testSetStakingContract() public view {
        assertEq(address(votingContract.stakingContract()), address(stakingContract));
    }

    function testSetSafeAddress() public {
        address newSafe = makeAddr("newSafe");

        vm.prank(owner);
        votingContract.setSafeAddress(newSafe);

        assertEq(votingContract.safeAddress(), newSafe);
    }

    // -- 2. ADMIN & ACCESS CONTROL TESTS --

    function testAddAdmin() public {
        vm.prank(owner);
        votingContract.addAdmin(admin1);

        assertTrue(votingContract.authorizedAdmins(admin1));
        assertEq(votingContract.adminCount(), 1);
    }
}
