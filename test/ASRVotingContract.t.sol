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

    // ========== HELPER FUNCTIONS ==========

    function _setupQuarterAndFunding() internal {
        vm.startPrank(owner);
        votingContract.addAdmin(admin1);
        vm.stopPrank();

        vm.prank(admin1);
        votingContract.startNewQuarter();

        vm.prank(owner);
        votingContract.setQuarterAsrAndFund(1, 100_000 ether);
    }

    function _setupStakingUsers() internal {
        vm.prank(user1);
        stakingContract.stake(1000 ether);

        vm.prank(user2);
        stakingContract.stake(1500 ether);
    }

    function _createTestProposal() internal returns (uint256) {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.prank(proposer1);
        return votingContract.createProposal(
            "Test Proposal",
            "Test Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );
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

    function testRemoveAdmin() public {
        vm.startPrank(owner);

        votingContract.addAdmin(admin1);
        votingContract.addAdmin(admin2);

        votingContract.removeAdmin(admin1);

        assertFalse(votingContract.authorizedAdmins(admin1));
        assertTrue(votingContract.authorizedAdmins(admin2));
        assertEq(votingContract.adminCount(), 1);
    }

    function testCannotRemoveLastAdmin() public {
        vm.startPrank(owner);

        votingContract.addAdmin(admin1);

        vm.expectRevert("Cannot remove last admin");
        votingContract.removeAdmin(admin1);

        vm.stopPrank();
    }

    function testOnlyOwnerCanAddAdmin() public {
        vm.prank(admin1);
        vm.expectRevert("ASRVotingContract: Caller is not the owner");
        votingContract.addAdmin(admin2);
    }

    function testAddAuthorizedProposer() public {
        vm.startPrank(owner);
        votingContract.addAdmin(admin1);
        vm.stopPrank();

        vm.prank(admin1);
        votingContract.addAuthorizedProposer(proposer1);

        assertTrue(votingContract.authorizedProposers(proposer1));
    }

    function testRemoveAuthorizedProposer() public {
        vm.startPrank(owner);
        votingContract.addAdmin(admin1);
        vm.stopPrank();

        vm.startPrank(admin1);
        votingContract.addAuthorizedProposer(proposer1);
        votingContract.removeAuthorizedProposer(proposer1);
        vm.stopPrank();

        assertFalse(votingContract.authorizedProposers(proposer1));
    }

    function testOnlyAuthorizedAdminCanManageProposers() public {
        vm.prank(user1);
        vm.expectRevert("Not authorized");
        votingContract.addAuthorizedProposer(proposer1);
    }

    function testUnauthorizedCannotCreateProposal() public {
        // Setup quarter and funding
        _setupQuarterAndFunding();

        vm.prank(user1);
        vm.expectRevert("ASRVotingContract: Caller is not an authorized proposer");
        votingContract.createProposal(
            "Test Proposal",
            "Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );
    }

    // -- 3. QUARTERLY MANAGEMENT TESTS --

    function testStartNewQuarter() public {
        vm.prank(owner);
        votingContract.addAdmin(admin1);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        assertEq(votingContract.currentQuarter(), 1);
        assertFalse(votingContract.proposalCreationEnabled());
    }

    function testCannotStartQuarterEarly() public {
        vm.prank(owner);
        votingContract.addAdmin(admin1);

        vm.startPrank(admin1);
        votingContract.startNewQuarter();

        vm.expectRevert("Quarter not ended");
        votingContract.startNewQuarter();

        vm.stopPrank();
    }

    function testQuarterFinalization() public {
        vm.prank(owner);
        votingContract.addAdmin(admin1);

        vm.startPrank(admin1);

        votingContract.startNewQuarter();

        skip(QUARTER_DURATION + 1 days);
        votingContract.startNewQuarter();

        assertTrue(votingContract.quarterDistributed(1));
        assertGt(votingContract.quarterClaimDeadline(1), 0);

        vm.stopPrank();
    }

    function testSetQuarterAsrAndFund() public {
        vm.prank(owner);
        votingContract.addAdmin(admin1);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        uint256 asrAmount = 100000 ether;

        vm.prank(owner);
        votingContract.setQuarterAsrAndFund(1, asrAmount);

        assertEq(votingContract.quarterASRPool(1), asrAmount);
        assertTrue(votingContract.quarterAsrFunded(1));
        assertTrue(votingContract.proposalCreationEnabled());
        assertEq(stakingToken.balanceOf(address(votingContract)), asrAmount);
    }

    function testCannotFundQuarterTwice() public {
        vm.prank(owner);
        votingContract.addAdmin(admin1);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        uint256 asrAmount = 100000 ether;

        vm.startPrank(owner);
        votingContract.setQuarterAsrAndFund(1, asrAmount);

        vm.expectRevert("Quarter already funded");
        votingContract.setQuarterAsrAndFund(1, asrAmount);

        vm.stopPrank();
    }

    function testCannotFundWithZeroAmount() public {
        vm.prank(owner);
        votingContract.addAdmin(admin1);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        vm.prank(owner);
        vm.expectRevert("Invalid ASR amount");
        votingContract.setQuarterAsrAndFund(1, 0);
    }

    function testProposalCreationDisabledWithoutFunding() public {
        vm.startPrank(owner);
        votingContract.addAdmin(admin1);
        votingContract.addAuthorizedProposer(proposer1);
        vm.stopPrank();

        vm.prank(admin1);
        votingContract.startNewQuarter();

        vm.prank(proposer1);
        vm.expectRevert("Proposal creation disabled - ASR not funded");
        votingContract.createProposal(
            "Test Proposal",
            "Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );
    }

    function testProposalCreationEnabledAfterFunding() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.prank(proposer1);
        uint256 proposalId = votingContract.createProposal(
            "Test Proposal",
            "Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        assertEq(proposalId, 1);
    }

    function testGetCurrentQuarter() public {
        vm.prank(owner);
        votingContract.addAdmin(admin1);

        assertEq(votingContract.getCurrentQuarter(), 0);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        assertEq(votingContract.getCurrentQuarter(), 1);
    }

    function testQuarterStatusTracking() public {
        _setupQuarterAndFunding();

        (
            bool funded,
            bool distributed,
            uint256 asrPool,
            uint256 claimDeadline,
            bool claimActive,
            uint256 totalVotingPower
        ) = votingContract.getQuarterStatus(1);

        assertTrue(funded);
        assertFalse(distributed);
        assertEq(asrPool, 100000 ether);
        assertEq(claimDeadline, 0);
        assertFalse(claimActive);
        assertEq(totalVotingPower, 0);
    }

    function testCannotStartQuarterIfProposalActive() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        skip(QUARTER_DURATION - 1 days);

        vm.prank(proposer1);
        uint256 proposalId = votingContract.createProposal(
            "Test Proposal",
            "Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        assertEq(proposalId, 1);

        skip(2 days);

        vm.prank(admin1);
        vm.expectRevert("Previous quarter proposal still active");
        votingContract.startNewQuarter();

        skip(6 days);
        vm.startPrank(admin1);
        votingContract.resolveProposal(1);
        votingContract.startNewQuarter();
        vm.stopPrank();
    }

    // -- 4. PROPOSAL CREATION TESTS --

    function testCreateBinaryProposal() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.prank(proposer1);
        uint256 proposalId = votingContract.createProposal(
            "Binary Proposal",
            "Should we do X?",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        assertEq(proposalId, 1);
        assertEq(votingContract.proposalCounter(), 1);
        assertEq(votingContract.activeProposalCount(), 1);
        assertEq(votingContract.proposalQuarter(proposalId), 1);
    }

    function testCreateMultiChoiceProposal() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        string[] memory choices = new string[](3);
        choices[0] = "Option-A";
        choices[1] = "Option-B";
        choices[2] = "Option-C";

        vm.prank(proposer1);
        uint256 proposalId = votingContract.createProposal(
            "Multichoice proposal",
            "Which option do you prefer?",
            ASRVotingContract.ProposalCategory.TREASURY_ACTION,
            ASRVotingContract.ProposalType.MULTICHOICE,
            choices,
            "",
            address(0),
            0
        );

        assertEq(proposalId, 1);
        assertEq(votingContract.proposalCounter(), 1);
    }

    function testCreateProposalCallsStakingContract() public {
        _setupQuarterAndFunding();
        _setupStakingUsers();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.prank(proposer1);
        uint256 proposalId = votingContract.createProposal(
            "Test Proposal",
            "Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );
        delete proposalId;
        assertTrue(stakingContract.hasActiveProposals());
        assertEq(stakingContract.activeProposalCount(), 1);
    }

    function testCannnotCreateProposalWithoutFunding() public {
        vm.startPrank(owner);
        votingContract.addAdmin(admin1);
        votingContract.addAuthorizedProposer(proposer1);
        vm.stopPrank();

        vm.prank(admin1);
        votingContract.startNewQuarter();

        vm.prank(proposer1);
        vm.expectRevert("Proposal creation disabled - ASR not funded");
        votingContract.createProposal(
            "Test proposal",
            "Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );
    }

    function testCannotExceedMaxActiveProposals() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.startPrank(proposer1);
        for (uint256 i = 0; i < 3; i++) {
            votingContract.createProposal(
                string(abi.encodePacked("Proposal", i)),
                "Description",
                ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
                ASRVotingContract.ProposalType.BINARY,
                new string[](0),
                "",
                address(0),
                0
            );
        }

        vm.expectRevert("Too many active proposals");
        votingContract.createProposal(
            "Fourth Proposal",
            "Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );
        vm.stopPrank();
    }

    function testProposalIdIncrementsCorrectly() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.startPrank(proposer1);

        uint256 id1 = votingContract.createProposal(
            "Proposal 1",
            "Desc",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        uint256 id2 = votingContract.createProposal(
            "Proposal 2",
            "Desc",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(votingContract.proposalCounter(), 2);
    }

    function testProposalMetadataStoredCorrectly() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        string memory title = "Test Proposal";
        string memory description = "Test Description";

        vm.prank(proposer1);
        uint256 proposalId = votingContract.createProposal(
            title,
            description,
            ASRVotingContract.ProposalCategory.TREASURY_ACTION,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        (
            string memory storedTitle,
            string memory storedDescription,
            address proposer,
            ASRVotingContract.ProposalState state,
            ,
            ,
            string[] memory choices,
        ) = votingContract.getProposalDetails(proposalId);

        assertEq(storedTitle, title);
        assertEq(storedDescription, description);
        assertEq(proposer, proposer1);
        assertEq(uint256(state), uint256(ASRVotingContract.ProposalState.ACTIVE));
        assertEq(choices.length, 3); // Binary proposal has 3 choices
        assertEq(choices[0], "For");
        assertEq(choices[1], "Against");
        assertEq(choices[2], "Abstrain");
    }

    function testProposalQuarterAssignment() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.prank(proposer1);
        uint256 proposalId = votingContract.createProposal(
            "Test Proposal",
            "Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        assertEq(votingContract.proposalQuarter(proposalId), 1);
    }

    function testInvalidProposalCreationFails() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.startPrank(proposer1);

        vm.expectRevert("Title required");
        votingContract.createProposal(
            "",
            "Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.expectRevert("Description required");
        votingContract.createProposal(
            "Title",
            "",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.stopPrank();
    }

    function testCreateProposalDifferentCategories() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.startPrank(proposer1);

        votingContract.createProposal(
            "Parameter Proposer",
            "Desc",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        votingContract.createProposal(
            "Treasury Proposer",
            "Desc",
            ASRVotingContract.ProposalCategory.TREASURY_ACTION,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        votingContract.createProposal(
            "Emergency Proposal",
            "Desc",
            ASRVotingContract.ProposalCategory.EMERGENCY_ACTION,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.stopPrank();

        assertEq(votingContract.proposalCounter(), 3);
    }

    // -- 5. VOTING MECHANISM TESTS --

    function testVoteOnBinaryProposal() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 0);

        (,,,,, uint256 totalVotes, string[] memory choices, uint256[] memory voteCounts) =
            votingContract.getProposalDetails(proposalId);

        assertEq(totalVotes, 1000 ether);
        assertEq(choices[0], "For");
        assertEq(voteCounts[0], 1000 ether);
        assertEq(voteCounts[1], 0 ether);
        assertEq(voteCounts[2], 0 ether);
    }

    function testVoteOnMultiChoiceProposal() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        string[] memory choices = new string[](3);
        choices[0] = "Option-A";
        choices[1] = "Option-B";
        choices[2] = "Option-C";

        _setupStakingUsers();

        vm.prank(proposer1);
        uint256 proposalId = votingContract.createProposal(
            "Multi choice",
            "Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.MULTICHOICE,
            choices,
            "",
            address(0),
            0
        );

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        (,,,,, uint256 totalVotes,, uint256[] memory voteCounts) = votingContract.getProposalDetails(proposalId);

        assertEq(voteCounts[1], 1000 ether);
        assertEq(totalVotes, 1000 ether);
    }

    function testVotingSelectiveSnapshot() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user2);
        stakingContract.stake(500 ether);

        vm.prank(user2);
        votingContract.vote(proposalId, 1);

        (,,,,,,, uint256[] memory voteCounts) = votingContract.getProposalDetails(proposalId);

        assertEq(voteCounts[1], 1500 ether);
    }

    function testCannotVoteTwice() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.startPrank(user1);
        votingContract.vote(proposalId, 1);

        vm.expectRevert("Already voted");
        votingContract.vote(proposalId, 0);

        vm.stopPrank();
    }

    function testCannotVoteWithZeroPower() public {
        uint256 proposalId = _createTestProposal();

        vm.prank(user2);
        vm.expectRevert("No voting power");
        votingContract.vote(proposalId, 1);
    }

    function testCannotVoteOnInactiveProposal() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        vm.prank(user1);
        vm.expectRevert("Proposal not active");
        votingContract.vote(proposalId, 1);
    }

    function testCannotVoteAfterDeadline() public {
        uint256 proposalId = _createTestProposal();
        _setupStakingUsers();

        vm.warp(block.timestamp + 8 days);

        vm.prank(user1);
        vm.expectRevert("Voting period ended");
        votingContract.vote(proposalId, 1);
    }

    function testVotingPowerCalculatedCorrectly() public {
        vm.prank(user1);
        stakingContract.stake(1000 ether);

        vm.prank(user2);
        stakingContract.stake(2000 ether);
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        vm.prank(user2);
        votingContract.vote(proposalId, 1);

        (,,,,, uint256 totalVotes,, uint256[] memory voteCounts) = votingContract.getProposalDetails(proposalId);

        assertEq(totalVotes, 3000 ether);
        assertEq(voteCounts[1], 3000 ether);
    }

    function testVoteCountsAccumulate() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        vm.prank(user2);
        votingContract.vote(proposalId, 0);

        (,,,,, uint256 totalVotes,, uint256[] memory voteCounts) = votingContract.getProposalDetails(proposalId);

        assertEq(totalVotes, 2500 ether);
        assertEq(voteCounts[1], 1000 ether);
        assertEq(voteCounts[0], 1500 ether);
    }

    function testVotingTracksAsrParticipation() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        assertEq(votingContract.userQuarterVotingPower(user1, 1), 1000 ether);
        assertEq(votingContract.quarterTotalVotingPower(1), 1000 ether);
    }

    function testInvalidChoiceIndexFails() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        vm.expectRevert("Invalid choice");
        votingContract.vote(proposalId, 5);
    }

    // -- 6. PROPOSAL RESOLUTION TESTS --

    function testResolveProposalAfterVotingEnds() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 0);

        skip(8 days);

        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        (,,, ASRVotingContract.ProposalState state,,,,) = votingContract.getProposalDetails(proposalId);
        assertEq(uint256(state), uint256(ASRVotingContract.ProposalState.SUCCEEDED));
        assertEq(votingContract.activeProposalCount(), 0);
    }

    function testCannotResolveActionProposal() public {
        uint256 proposalId = _createTestProposal();

        vm.prank(admin1);
        vm.expectRevert("Voting still active");
        votingContract.resolveProposal(proposalId);
    }

    function testBinaryProposalPassesWithMajority() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 0);

        vm.prank(user2);
        votingContract.vote(proposalId, 0);

        vm.warp(block.timestamp + 8 days);

        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        (,,, ASRVotingContract.ProposalState state,,,,) = votingContract.getProposalDetails(proposalId);
        assertEq(uint256(state), uint256(ASRVotingContract.ProposalState.SUCCEEDED));
    }

    function testBinaryProposalFailsWithoutQuorum() public {
        _setupStakingUsers();
        address tempUser = makeAddr("tempUser");

        vm.prank(user2);
        stakingToken.transfer(tempUser, 10 ether);

        vm.startPrank(tempUser);
        stakingToken.approve(address(stakingContract), 10 ether);
        stakingContract.stake(10 ether);
        vm.stopPrank();

        uint256 proposalId = _createTestProposal();

        vm.prank(tempUser);
        votingContract.vote(proposalId, 0);

        vm.warp(block.timestamp + 8 days);

        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        (,,, ASRVotingContract.ProposalState state,,,,) = votingContract.getProposalDetails(proposalId);
        assertEq(uint256(state), uint256(ASRVotingContract.ProposalState.DEFEATED));
    }

    function testBinaryProposalFailsWithoutApproval() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        vm.prank(user2);
        votingContract.vote(proposalId, 1);

        skip(8 days);

        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        (,,, ASRVotingContract.ProposalState state,,,,) = votingContract.getProposalDetails(proposalId);
        assertEq(uint256(state), uint256(ASRVotingContract.ProposalState.DEFEATED));
    }

    function testMultiChoiceProposalResolution() public {
        _setupQuarterAndFunding();
        _setupStakingUsers();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        string[] memory choices = new string[](3);
        choices[0] = "Option A";
        choices[1] = "Option B";
        choices[2] = "Option C";

        vm.prank(proposer1);
        uint256 proposalId = votingContract.createProposal(
            "Multi Choice",
            "Description",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.MULTICHOICE,
            choices,
            "",
            address(0),
            0
        );

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        vm.prank(user2);
        votingContract.vote(proposalId, 2);

        vm.warp(block.timestamp + 8 days);

        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        (,,, ASRVotingContract.ProposalState state,,,,) = votingContract.getProposalDetails(proposalId);
        assertEq(uint256(state), uint256(ASRVotingContract.ProposalState.SUCCEEDED));
    }

    function testProposalResolutionCallsStakingContract() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 0);

        vm.warp(block.timestamp + 8 days);

        assertEq(stakingContract.activeProposalCount(), 1);

        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        assertEq(stakingContract.activeProposalCount(), 0);
        assertFalse(stakingContract.hasActiveProposals());
    }

    function testActiveProposalCountDecrements() public {
        _setupQuarterAndFunding();

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        _setupStakingUsers();

        vm.startPrank(proposer1);
        uint256 proposal1 = votingContract.createProposal(
            "Proposal 1",
            "Desc",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );
        votingContract.createProposal(
            "Proposal 2",
            "Desc",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );
        vm.stopPrank();

        assertEq(votingContract.activeProposalCount(), 2);

        vm.prank(user1);
        votingContract.vote(proposal1, 1);

        vm.warp(block.timestamp + 8 days);

        vm.prank(admin1);
        votingContract.resolveProposal(proposal1);

        assertEq(votingContract.activeProposalCount(), 1);
    }

    function testProposalStateUpdatesCorrectly() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        (,,, ASRVotingContract.ProposalState initialState,,,,) = votingContract.getProposalDetails(proposalId);
        assertEq(uint256(initialState), uint256(ASRVotingContract.ProposalState.ACTIVE));

        vm.prank(user1);
        votingContract.vote(proposalId, 0);

        vm.warp(block.timestamp + 8 days);

        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        (,,, ASRVotingContract.ProposalState finalState,,,,) = votingContract.getProposalDetails(proposalId);
        assertEq(uint256(finalState), uint256(ASRVotingContract.ProposalState.SUCCEEDED));
    }

    // -- 7. ASR DISTRIBUTION TESTS --

    function testAsrVotingPowerTracking() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        assertEq(votingContract.userQuarterVotingPower(user1, 1), 1000 ether);
        assertEq(votingContract.quarterTotalVotingPower(1), 1000 ether);
    }

    function testCumulativeVoteingPowerPerQuarter() public {
        _setupStakingUsers();
        uint256 proposal1 = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposal1, 0);

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.prank(proposer1);
        uint256 proposal2 = votingContract.createProposal(
            "Proposal 2",
            "Desc",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.prank(user1);
        votingContract.vote(proposal2, 0);

        assertEq(votingContract.userQuarterVotingPower(user1, 1), 2000 ether);
        assertEq(votingContract.quarterTotalVotingPower(1), 2000 ether);
    }

    function testAsrRewardCalculation() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 0);

        vm.prank(user2);
        votingContract.vote(proposalId, 0);

        uint256 expectedReward = votingContract.calculateAsrReward(user1, 1);

        uint256 calc = 1000 ether * 100_000 ether; // userVotingPower * asrRewardPool
        uint256 expectedCalculation = (calc / 2500 ether); // (userVotingPower * asrRewardPool) / totalVotingPower

        assertEq(expectedReward, expectedCalculation);
    }

    function testAsrRewardCalculationWithMultipleProposals() public {
        _setupStakingUsers();
        uint256 proposal1 = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposal1, 0);

        vm.prank(user2);
        votingContract.vote(proposal1, 0);

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.prank(proposer1);
        uint256 proposal2 = votingContract.createProposal(
            "Proposal 2",
            "Desc",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.prank(user1);
        votingContract.vote(proposal2, 0);

        vm.prank(user2);
        votingContract.vote(proposal2, 0);

        uint256 reward = votingContract.calculateAsrReward(user1, 1);
        uint256 calc = 2000 ether * 100_000 ether; // userVotingPower * asrRewardPool
        uint256 expectedCalculation = (calc / 5000 ether); // (userVotingPower * asrRewardPool) / totalVotingPower

        assertEq(reward, expectedCalculation);
    }

    function testAsrRewardProportionalDistribution() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        vm.prank(user2);
        votingContract.vote(proposalId, 1);

        uint256 reward1 = votingContract.calculateAsrReward(user1, 1);
        uint256 reward2 = votingContract.calculateAsrReward(user2, 1);

        assertEq(reward2, 60000 ether); // Lazy to eval

        assertEq(reward1 + reward2, 100_000 ether);
    }

    function testQuarterlyAsrPoolManagement() public {
        _setupQuarterAndFunding();

        assertEq(votingContract.quarterASRPool(1), 100_000 * 1e18);
        assertTrue(votingContract.quarterAsrFunded(1));

        assertEq(stakingToken.balanceOf(address(votingContract)), 100_000 * 1e18);
    }

    function testAsrTrackingAcrossProposals() public {
        _setupStakingUsers();
        uint256 proposal1 = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposal1, 1);

        uint256 quarter1Power = votingContract.userQuarterVotingPower(user1, 1);

        vm.prank(owner);
        votingContract.addAuthorizedProposer(proposer1);

        vm.prank(proposer1);
        uint256 proposal2 = votingContract.createProposal(
            "Proposal 2",
            "Desc",
            ASRVotingContract.ProposalCategory.PARAMETER_CHANGE,
            ASRVotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.prank(user1);
        votingContract.vote(proposal2, 0);

        uint256 quarter1PowerAfter = votingContract.userQuarterVotingPower(user1, 1);

        assertGt(quarter1PowerAfter, quarter1Power);
        assertEq(quarter1PowerAfter, quarter1Power + 1000 ether);
    }

    // -- 8. ASR CLAIMING TESTS --
    function testClaimAsrRewardsForCompletedQuarter() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        // End quarter
        vm.warp(block.timestamp + QUARTER_DURATION + 1);

        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter(); // Finalizes quarter 1

        uint256[] memory quarters = new uint256[](1);
        quarters[0] = 1;

        uint256 initialStakedBalance = stakingContract.getStakedAmount(user1);

        vm.prank(user1);
        votingContract.claimAsrRewards(quarters);

        uint256 finalStakedBalance = stakingContract.getStakedAmount(user1);

        // ASR should be added to staked balance
        assertGt(finalStakedBalance, initialStakedBalance);
        assertTrue(votingContract.userQuarterClaimed(user1, 1));
    }

    function testCannotClaimBeforeQuarterEnds() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        uint256[] memory quarters = new uint256[](1);
        quarters[0] = 1;

        vm.prank(user1);
        vm.expectRevert("Quarter not completed");
        votingContract.claimAsrRewards(quarters);
    }

    function testCannotClaimTwice() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        // End quarter
        vm.warp(block.timestamp + QUARTER_DURATION + 1);

        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        uint256[] memory quarters = new uint256[](1);
        quarters[0] = 1;

        vm.prank(user1);
        votingContract.claimAsrRewards(quarters);

        vm.prank(user1);
        vm.expectRevert("Already claimed");
        votingContract.claimAsrRewards(quarters);
    }

    function testCannotClaimAfterDeadline() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        // End quarter
        vm.warp(block.timestamp + QUARTER_DURATION + 1);

        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        // Fast forward past claim deadline (30 days)
        vm.warp(block.timestamp + 31 days);

        uint256[] memory quarters = new uint256[](1);
        quarters[0] = 1;

        vm.prank(user1);
        vm.expectRevert("Claim deadline passed");
        votingContract.claimAsrRewards(quarters);
    }

    function testPartialAsrClaiming() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        // Only user1 votes (user2 doesn't vote)
        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        // End quarter
        vm.warp(block.timestamp + QUARTER_DURATION + 1);

        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        uint256[] memory quarters = new uint256[](1);
        quarters[0] = 1;

        // user1 can claim
        vm.prank(user1);
        votingContract.claimAsrRewards(quarters);

        // user2 cannot claim (no voting power)
        uint256 user2Reward = votingContract.calculateAsrReward(user2, 1);
        assertEq(user2Reward, 0);
    }

    function testZeroAsrRewardsClaim() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        // user1 votes, user2 doesn't
        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        // End quarter
        vm.warp(block.timestamp + QUARTER_DURATION + 1);

        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        uint256[] memory quarters = new uint256[](1);
        quarters[0] = 1;

        uint256 initialBalance = stakingContract.getStakedAmount(user2);

        // user2 claims (should be no-op due to zero rewards)
        vm.prank(user2);
        votingContract.claimAsrRewards(quarters);

        uint256 finalBalance = stakingContract.getStakedAmount(user2);

        assertEq(finalBalance, initialBalance); // No change
    }

    // -- 9. ASR DEADLINE & RECOVERY TESTS --

    function testClaimDeadlineEnforcement() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        // End quarter
        vm.warp(block.timestamp + QUARTER_DURATION + 1);
        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        uint256 deadline = votingContract.quarterClaimDeadline(1);
        assertEq(deadline, block.timestamp + 30 days);
    }

    function testRecoverUnclaimedAsr() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        // End quarter
        vm.warp(block.timestamp + QUARTER_DURATION + 1);

        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        // Fast forward past deadline
        vm.warp(block.timestamp + 31 days);

        uint256 ownerBalanceBefore = stakingToken.balanceOf(owner);
        uint256 expectedUnclaimed = 100_000 * 1e18; // Full pool since no one claimed

        vm.prank(owner);
        votingContract.recoverUnclaimedAsr(1);

        uint256 ownerBalanceAfter = stakingToken.balanceOf(owner);

        assertEq(ownerBalanceAfter, ownerBalanceBefore + expectedUnclaimed);
    }

    function testCannotRecoverBeforeDeadline() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        // End quarter
        vm.warp(block.timestamp + QUARTER_DURATION + 1);

        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        // Try to recover before deadline
        vm.prank(owner);
        vm.expectRevert("Claim period not ended");
        votingContract.recoverUnclaimedAsr(1);
    }

    function testRecoverUnclaimedAsrCalculation() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        // Both users vote
        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        vm.prank(user2);
        votingContract.vote(proposalId, 1);

        // End quarter
        vm.warp(block.timestamp + QUARTER_DURATION + 1);

        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        // Only user1 claims
        uint256[] memory quarters = new uint256[](1);
        quarters[0] = 1;

        uint256 user1Reward = votingContract.calculateAsrReward(user1, 1);

        vm.prank(user1);
        votingContract.claimAsrRewards(quarters);

        // Fast forward past deadline
        vm.warp(block.timestamp + 31 days);

        uint256 ownerBalanceBefore = stakingToken.balanceOf(owner);
        uint256 expectedUnclaimed = 100_000 * 1e18 - user1Reward;

        vm.prank(owner);
        votingContract.recoverUnclaimedAsr(1);

        uint256 ownerBalanceAfter = stakingToken.balanceOf(owner);

        assertEq(ownerBalanceAfter, ownerBalanceBefore + expectedUnclaimed);
    }

    function testOnlyOwnerCanRecoverAsr() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        // End quarter and wait past deadline
        vm.warp(block.timestamp + QUARTER_DURATION + 1);

        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        vm.warp(block.timestamp + 31 days);

        vm.prank(user1);
        vm.expectRevert("ASRVotingContract: Caller is not the owner");
        votingContract.recoverUnclaimedAsr(1);
    }

    // -- 10. ASR VIEW FUNCTION TESTS --

    function testCanUserClaimValidQuarter() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        // End quarter
        vm.warp(block.timestamp + QUARTER_DURATION + 1);

        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        (bool canClaim, string memory reason, uint256 asrAmount, uint256 deadline) =
            votingContract.canUserClaim(user1, 1);

        assertTrue(canClaim);
        assertEq(keccak256(bytes(reason)), keccak256(bytes("Can claim")));
        assertGt(asrAmount, 0);
        assertGt(deadline, 0);
    }

    function testCanUserClaimInvalidScenarios() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        // Test before quarter completion
        (bool canClaim1, string memory reason1,,) = votingContract.canUserClaim(user1, 1);
        assertFalse(canClaim1);
        assertEq(keccak256(bytes(reason1)), keccak256(bytes("Quarter not completed")));

        // End quarter
        vm.warp(block.timestamp + QUARTER_DURATION + 1);

        votingContract.resolveProposal(proposalId);

        vm.prank(admin1);
        votingContract.startNewQuarter();

        // Test after claiming
        uint256[] memory quarters = new uint256[](1);
        quarters[0] = 1;

        vm.prank(user1);
        votingContract.claimAsrRewards(quarters);

        (bool canClaim2, string memory reason2,,) = votingContract.canUserClaim(user1, 1);
        assertFalse(canClaim2);
        assertEq(keccak256(bytes(reason2)), keccak256(bytes("Already claimed")));

        // Test after deadline
        vm.warp(block.timestamp + 31 days);

        (bool canClaim3, string memory reason3,,) = votingContract.canUserClaim(user2, 1);
        assertFalse(canClaim3);
        assertEq(keccak256(bytes(reason3)), keccak256(bytes("Claim deadline passed")));
    }

    function testGetQuarterStatus() public {
        _setupQuarterAndFunding();

        (
            bool funded,
            bool distributed,
            uint256 asrPool,
            uint256 claimDeadline,
            bool claimActive,
            uint256 totalVotingPower
        ) = votingContract.getQuarterStatus(1);

        assertTrue(funded);
        assertFalse(distributed);
        assertEq(asrPool, 100_000 ether);
        assertEq(claimDeadline, 0);
        assertFalse(claimActive);
        assertEq(totalVotingPower, 0);
    }

    function testGetUserAsrInfo() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        uint256[] memory quarters = new uint256[](1);
        quarters[0] = 1;

        (uint256[] memory votingPowers, uint256[] memory asrRewards, bool[] memory claimed, bool[] memory canClaim) =
            votingContract.getUserAsrInfo(user1, quarters);

        assertEq(votingPowers[0], 1000 ether);
        assertGt(asrRewards[0], 0);
        assertFalse(claimed[0]);
        assertFalse(canClaim[0]); // Quarter not ended yet
    }

    function testCalculateAsrRewardEdgeCases() public {
        // Test with zero voting power
        uint256 reward1 = votingContract.calculateAsrReward(user1, 1);
        assertEq(reward1, 0);

        // Test with unfunded quarter
        vm.startPrank(owner);
        votingContract.addAdmin(admin1);
        vm.stopPrank();

        vm.prank(admin1);
        votingContract.startNewQuarter();

        uint256 reward2 = votingContract.calculateAsrReward(user1, 1);
        assertEq(reward2, 0);
    }

    function testAsrRewardWithZeroVotingPower() public {
        _setupQuarterAndFunding();

        uint256 reward = votingContract.calculateAsrReward(user1, 1);
        assertEq(reward, 0);
    }

    function testAsrRewardWithZeroTotalStaked() public {
        _setupQuarterAndFunding();

        // Don't stake anything, but somehow have voting power tracked
        // This shouldn't happen in practice, but test division by zero protection
        uint256 reward = votingContract.calculateAsrReward(user1, 1);
        assertEq(reward, 0);
    }

    // -- 11. PROPOSAL EXECUTION TESTS --

    function testExecutePassedProposal() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        // Vote and pass proposal
        vm.prank(user1);
        votingContract.vote(proposalId, 0);

        vm.prank(user2);
        votingContract.vote(proposalId, 0);

        // Resolve proposal
        vm.warp(block.timestamp + 8 days);

        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        // Wait for execution delay
        skip(8 days);

        vm.prank(admin1);
        votingContract.executeProposal(proposalId);

        (,,, ASRVotingContract.ProposalState state,,,,) = votingContract.getProposalDetails(proposalId);
        assertEq(uint256(state), uint256(ASRVotingContract.ProposalState.EXECUTED));
    }

    function testCannotExecuteFailedProposal() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        // Vote against proposal
        vm.prank(user1);
        votingContract.vote(proposalId, 1);

        vm.prank(user2);
        votingContract.vote(proposalId, 1);

        // Resolve proposal (should fail)
        vm.warp(block.timestamp + 8 days);

        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        vm.warp(block.timestamp + 3 days);

        vm.prank(admin1);
        vm.expectRevert("Proposal not passed");
        votingContract.executeProposal(proposalId);
    }

    function testCannotExecuteBeforeDelay() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        // Vote and pass proposal
        vm.prank(user1);
        votingContract.vote(proposalId, 0);

        vm.prank(user2);
        votingContract.vote(proposalId, 0);

        vm.warp(block.timestamp + 8 days);

        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        // Try to execute immediately
        vm.prank(admin1);
        vm.expectRevert("Execution delay not met");
        votingContract.executeProposal(proposalId);
    }

    function testCannotExecuteAfterGracePeriod() public {
        _setupStakingUsers();
        uint256 proposalId = _createTestProposal();

        // Vote and pass proposal
        vm.prank(user1);
        votingContract.vote(proposalId, 0);

        vm.prank(user2);
        votingContract.vote(proposalId, 0);

        vm.warp(block.timestamp + 8 days);

        vm.prank(admin1);
        votingContract.resolveProposal(proposalId);

        // Wait past grace period (execution delay + grace period)
        vm.warp(block.timestamp + 22 days);

        vm.prank(admin1);
        vm.expectRevert("Grace period expired");
        votingContract.executeProposal(proposalId);
    }

    // -- 12. SECURITY & EDGE CASE TESTS --
}
