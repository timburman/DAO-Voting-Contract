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
    mapping(uint256 => mapping(address => bool)) public hasVotes; // proposalId => (user => hasVoted)
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

    // -- Interface Support --
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
