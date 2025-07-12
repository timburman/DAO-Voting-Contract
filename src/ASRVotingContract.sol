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

    // -- AUTHORIZATION --
    mapping(address => bool) public authorizedProposers;

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
        // Execution details
        address[] targets;
        bytes[] calldatas;
        // Timing
        uint256 startTime;
        uint256 endTime;
        uint256 executionTime;
        uint256 gracePeriodEnd;
        // Snapshot details
        uint256 snapShotBlock;
        uint256 totalVotingPower;
        // Voting details
        string[] choices;
        uint256 totalVotes;
        // State
        bool executed;
        bool cancelled;
        address proposer;
    }

    // -- Mappings --

    // Proposal Storage
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(uint256 => uint256)) public proposalChoiceVotes; // proposalId => (choiceIndex => votes)
    mapping(uint256 => mapping(address => bool)) public hasVoted; // proposalId => (user => hasVoted)
    mapping(uint256 => mapping(address => uint256)) public userVotingPower; // proposalId => (user => votingPower)
    mapping(uint256 => mapping(address => uint256)) public userVoteChoice; // proposalId => (user => choiceIndex)

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
        uint256 snapshotBlock
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

    // -- Initializer --
    function initialize(address _stakingContract, address _proposalManager, address _owner) public initializer {
        require(_stakingContract != address(0), "ASRVotingContract: Staking contract address cannot be zero");
        require(_proposalManager != address(0), "ASRVotingContract: Proposal manager address cannot be zero");
        require(_owner != address(0), "ASRVotingContract: Owner address cannot be zero");

        __ReentrancyGuard_init();

        stakingContract = ASRStakingContract(_stakingContract);
        proposalManager = _proposalManager;
        owner = _owner;

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
        address[] memory targets,
        bytes[] memory calldatas,
        string[] memory choices
    ) external onlyAuthorizedProposer nonReentrant returns (uint256) {
        require(bytes(title).length > 0, "Empty title");
        require(bytes(description).length > 0, "Empty description");
        require(targets.length == calldatas.length, "Array length mismatch");

        if (proposalType == ProposalType.BINARY) {
            require(choices.length == 0, "Binary proposals cannot have choices");
        } else {
            require(choices.length >= 2, "Need at least 2 choices for multi-choice");
            require(choices.length <= 10, "Too many choices (max 10)");
        }

        proposalCounter++;
        uint256 proposalId = proposalCounter;

        uint256 snapshotBlock = block.number;
        uint256 totalVotingPower = stakingContract.getTotalStaked();
        require(totalVotingPower > 0, "No staked tokens available for voting");

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + VOTING_PERIOD;
        uint256 executionDelay = categoryRequirements[category].executionDelay;
        uint256 executionTime = endTime + executionDelay;
        uint256 gracePeriodEnd = executionTime + GRACE_PERIOD;

        // Proposal Creation
        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.title = title;
        proposal.description = description;
        proposal.category = category;
        proposal.proposalType = proposalType;
        proposal.targets = targets;
        proposal.calldatas = calldatas;
        proposal.startTime = startTime;
        proposal.endTime = endTime;
        proposal.executionTime = executionTime;
        proposal.gracePeriodEnd = gracePeriodEnd;
        proposal.snapShotBlock = snapshotBlock;
        proposal.totalVotingPower = totalVotingPower;
        proposal.proposer = msg.sender;

        if (proposalType == ProposalType.BINARY) {
            proposal.choices.push("For");
            proposal.choices.push("Against");
            proposal.choices.push("Abstain");
        } else {
            for (uint256 i = 0; i < choices.length; i++) {
                require(bytes(choices[i]).length > 0, "Empty choice");
                proposal.choices.push(choices[i]);
            }
        }

        emit ProposalCreated(proposalId, msg.sender, title, category, proposalType, startTime, endTime, snapshotBlock);

        return proposalId;
    }

    // -- Voting --
    function vote(uint256 proposalId, uint256 choiceIndex, string memory reason)
        external
        validProposal(proposalId)
        nonReentrant
    {
        Proposal storage proposal = proposals[proposalId];

        require(block.timestamp >= proposal.startTime, "Voting has not started yet");
        require(block.timestamp < proposal.endTime, "Voting has ended");
        require(!proposal.cancelled, "Proposal cancelled");

        require(choiceIndex < proposal.choices.length, "Invalid choice index");
        require(!hasVoted[proposalId][msg.sender], "Already voted on this proposal");

        uint256 votingPower = stakingContract.getVotingPower(msg.sender);
    }

    // -- Interface Support --
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
