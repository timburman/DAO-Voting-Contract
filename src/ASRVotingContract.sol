// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "./ASRStakingContract.sol";

/**
 * @title ASRVotingContract
 * @dev Adanced voting system with snapshots, multi-choice proposals, categories, and ASR integration.
 * @notice Integrates with ASRStakingContract for voting power and activity tracking.
 */
contract ASRVotingContract is Initializable, ReentrancyGuardUpgradeable, IERC165 {
    // -- State Variables --
    ASRStakingContract public stakingContract;
    address public owner;
    address public pendingOwner;
    address public proposalManager;

    uint256 public proposalCounter;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant GRACE_PERIOD = 14 days;

    uint256 public constant MAX_ACTIVE_PROPOSALS = 3;
    uint256 public activeProposalCount;

    // -- AUTHORIZATION --
    mapping(address => bool) public authorizedAdmins;
    uint256 public adminCount;
    mapping(address => bool) public authorizedProposers;

    address public safeAddress;

    // -- Enums --
    enum ProposalCategory {
        PARAMETER_CHANGE,
        TREASURY_ACTION,
        EMERGENCY_ACTION,
        GOVERNANCE_CHANGE
    }

    enum ProposalType {
        BINARY,
        MULTICHOICE
    }

    enum ProposalState {
        PENDING,
        ACTIVE,
        SUCCEEDED,
        DEFEATED,
        QUEUED,
        EXECUTED,
        CANCELLED,
        EXPIRED
    }

    // -- Structs --

    struct ProposalRequirements {
        uint256 quorumPercentage;
        uint256 approvalThreshold;
        uint256 executionDelay;
    }

    struct Proposal {
        uint256 id;
        string title;
        string description;
        ProposalCategory category;
        ProposalType proposalType;
        address proposer;
        // Timing
        uint256 creationTime;
        uint256 votingEnd;
        uint256 executionTime;
        uint256 gracePeriodEnd;
        // Snapshot details
        uint256 snapshotPeriod;
        uint256 totalVotingPower;
        // Voting details
        string[] choices;
        uint256 totalVotes;
        uint256[] voteCounts;
        // State
        ProposalState state;
        // requirements
        uint256 quorumRequired;
        uint256 approvalRequired;
        bytes exectionData;
        address target;
        uint256 value;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) userVote;
    }

    // -- Mappings --

    // Proposal Storage
    mapping(uint256 => Proposal) public proposals;

    // Category Requirements
    mapping(ProposalCategory => ProposalRequirements) public categoryRequirements;

    // ASR Integration - Track voting activity per user per proposal
    mapping(address => mapping(uint256 => uint256)) public userProposalVotingPower;
    mapping(address => uint256[]) public userVotedProposals; // Track all proposals a user has voted on

    // -- Events --

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        ProposalCategory catrgory,
        ProposalType proposalType,
        uint256 startTime,
        uint256 endTime,
        uint256 period
    );

    event VoteCast(
        address indexed voter, uint256 indexed proposalId, uint256 choiceIndex, uint256 votingPower, string reason
    );

    event ProposalCancelled(uint256 indexed proposalId, address indexed canceller);

    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);

    event ProposerAdded(address indexed proposer);
    event ProposerRemoved(address indexed proposer);
    event ProposerManagerUpdated(address indexed newManager);
    event CategoryRequirementsUpdated(ProposalCategory indexed category);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // -- Modifiers --
    modifier onlyOwner() {
        require(msg.sender == owner, "ASRVotingContract: Caller is not the owner");
        _;
    }

    modifier onlyAuthorizedProposer() {
        require(
            authorizedProposers[msg.sender] || msg.sender == owner,
            "ASRVotingContract: Caller is not an authorized proposer"
        );
        _;
    }

    modifier onlyProposerManager() {
        require(msg.sender == proposalManager, "ASRVotingContract: Caller is not the proposal manager");
        _;
    }

    modifier validProposal(uint256 proposalId) {
        require(proposalId <= proposalCounter && proposalId > 0, "ASRVotingContract: Invalid proposal ID");
        _;
    }

    modifier onlyAuthorizedAdmin() {
        require(authorizedAdmins[msg.sender] || msg.sender == owner, "Not authorized");
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        require(proposalId > 0 && proposalId <= proposalCounter, "Invalid proposal");
        _;
    }

    modifier activeProposalLimit() {
        require(activeProposalCount < MAX_ACTIVE_PROPOSALS, "Too many active proposals");
        _;
    }

    // -- Initializer --
    function initialize(address _stakingContract, address _proposalManager, address _owner) public initializer {
        require(_stakingContract != address(0), "ASRVotingContract: Staking contract address cannot be zero");
        require(_proposalManager != address(0), "ASRVotingContract: Proposal manager address cannot be zero");
        require(_owner != address(0), "ASRVotingContract: Owner address cannot be zero");

        __ReentrancyGuard_init();

        stakingContract = ASRStakingContract(_stakingContract);
        proposalManager = _proposalManager;
        owner = _owner;
        activeProposalCount = 0;
        adminCount = 0;

        _setDefaultRequirements();
    }

    function _setDefaultRequirements() internal {
        // Parameter change - simple maority
        categoryRequirements[ProposalCategory.PARAMETER_CHANGE] =
            ProposalRequirements({quorumPercentage: 10, approvalThreshold: 51, executionDelay: 7 days});

        // Treasury action - higher threshold
        categoryRequirements[ProposalCategory.TREASURY_ACTION] =
            ProposalRequirements({quorumPercentage: 15, approvalThreshold: 60, executionDelay: 14 days});

        // Emergency action - high threshold, fast execution
        categoryRequirements[ProposalCategory.EMERGENCY_ACTION] =
            ProposalRequirements({quorumPercentage: 20, approvalThreshold: 75, executionDelay: 1 days});

        // Governance changes - supermajority
        categoryRequirements[ProposalCategory.GOVERNANCE_CHANGE] =
            ProposalRequirements({quorumPercentage: 25, approvalThreshold: 80, executionDelay: 21 days});
    }

    // -- Proposal Creation --

    function createProposal(
        string memory title,
        string memory description,
        ProposalCategory category,
        ProposalType proposalType,
        string[] memory choices,
        bytes memory executionData,
        address target,
        uint256 value
    ) external onlyAuthorizedProposer activeProposalLimit nonReentrant returns (uint256) {
        require(bytes(title).length > 0, "Title required");
        require(bytes(description).length > 0, "Description required");

        if (proposalType == ProposalType.BINARY) {
            require(choices.length == 0, "Binary proposals don't need choices");
        } else {
            require(choices.length > 2 && choices.length <= 10, "Invalid choice count");
        }

        proposalCounter++;
        uint256 proposalId = proposalCounter;

        uint256 period = stakingContract.createNewProposal(proposalId);
        activeProposalCount++;

        ProposalRequirements memory reqs = categoryRequirements[category];

        uint256 votingEnd = block.timestamp + VOTING_PERIOD;
        uint256 executionDelay = block.timestamp + reqs.executionDelay;

        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.title = title;
        proposal.description = description;
        proposal.proposer = msg.sender;
        proposal.category = category;
        proposal.proposalType = proposalType;
        proposal.creationTime = block.timestamp;
        proposal.votingEnd = votingEnd;
        proposal.executionTime = executionDelay;
        proposal.gracePeriodEnd = executionDelay + GRACE_PERIOD;
        proposal.state = ProposalState.ACTIVE;
        proposal.quorumRequired = reqs.quorumPercentage;
        proposal.approvalRequired = reqs.approvalThreshold;
        proposal.totalVotes = 0;
        proposal.exectionData = executionData;
        proposal.target = target;
        proposal.value = value;
        proposal.snapshotPeriod = period;

        if (proposalType == ProposalType.BINARY) {
            proposals[proposalId].choices.push("For");
            proposals[proposalId].choices.push("Against");
            proposals[proposalId].choices.push("Abstrain");
            proposals[proposalId].voteCounts.push(0);
            proposals[proposalId].voteCounts.push(0);
            proposals[proposalId].voteCounts.push(0);
        } else {
            for (uint256 i = 0; i < choices.length; i++) {
                proposals[proposalId].choices.push(choices[i]);
                proposals[proposalId].voteCounts.push(0);
            }
        }

        emit ProposalCreated(proposalId, msg.sender, title, category, proposalType, block.timestamp, votingEnd, period);

        return proposalId;
    }

    // -- Voting --
    function vote(uint256 proposalId, uint256 choiceIndex, string memory reason)
        external
        validProposal(proposalId)
        nonReentrant
    {
        Proposal storage proposal = proposals[proposalId];

        require(block.timestamp >= proposal.creationTime, "Voting has not started yet");
        require(block.timestamp < proposal.votingEnd, "Voting has ended");

        require(choiceIndex < proposal.choices.length, "Invalid choice index");

        uint256 votingPower = stakingContract.getVotingPower(msg.sender);
    }

    // -- Interface Support --
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
