// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./ReactiveStaking.sol";

/**
 * @title ReactiveVoting
 * @notice An abstract base contract for a governance system that uses a ReactiveStaking contract for voting power
 * @dev This contract provides the core logic for proposal creation, voting, resolution, and execution.
 * It is designed to be inherited. Core functions are `internal virtual` to allow for customizations.
 */
abstract contract ReactiveVoting is Initializable, ReentrancyGuardUpgradeable {
    // -- Stake Variables --

    /// @notice The instance of the ReactiveStaking contrract that manages balances and voting power
    ReactiveStaking internal _stakingContract;

    uint256 internal _proposalCounter;
    uint256 internal _activeProposalCount;

    // -- Constants --
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant MAX_ACTIVE_PROPOSALS = 3;

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
        uint256 creationTime;
        uint256 votingEnd;
        uint256 executionTime;
        uint256 gracePeriodEnd;
        string[] choices;
        uint256 totalVotes;
        uint256[] voteCounts;
        ProposalState state;
        uint256 quorumRequired; // In basis pointis, e.g., 1000 for 10%
        uint256 approvalRequired; // In percentage, e.g., 51 for 51%
        bytes executionData;
        address target;
        uint256 value;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) userVote;
    }

    // -- Mappings --
    mapping(uint256 => Proposal) internal _proposals;
    mapping(ProposalCategory => ProposalRequirements) internal _categoryRequirements;

    // -- Events --
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        ProposalCategory category,
        ProposalType proposalType
    );
    event VoteCast(address indexed voter, uint256 indexed proposalId, uint256 choiceIndex, uint256 votingPower);
    event ProposalCancelled(uint256 indexed proposalId);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalResolved(uint256 proposalId, ProposalState state);

    /**
     * @dev Initializes the contract. To be called from the child contract's initializer
     * @param stakingContractAddress The address of the deployed ReactiveStaking contract
     */
    function _initializeReactiveVoting(address stakingContractAddress) internal {
        require(stakingContractAddress != address(0), "Invalid Staking Contract");
        __ReentrancyGuard_init();
        _stakingContract = ReactiveStaking(stakingContractAddress);
        _setDefaultRequirements();
    }

    /**
     * @dev Sets default requirements for proposal categories. Can be overridden.
     */
    function _setDefaultRequirements() internal virtual {
        _categoryRequirements[ProposalCategory.PARAMETER_CHANGE] =
            ProposalRequirements({quorumPercentage: 10, approvalThreshold: 51, executionDelay: 7 days});
        _categoryRequirements[ProposalCategory.TREASURY_ACTION] =
            ProposalRequirements({quorumPercentage: 15, approvalThreshold: 60, executionDelay: 14 days});
        _categoryRequirements[ProposalCategory.EMERGENCY_ACTION] =
            ProposalRequirements({quorumPercentage: 20, approvalThreshold: 75, executionDelay: 1 days});
        _categoryRequirements[ProposalCategory.GOVERNANCE_CHANGE] =
            ProposalRequirements({quorumPercentage: 25, approvalThreshold: 80, executionDelay: 21 days});
    }

    // -- Public Functions --
    function createProposal(
        string memory title,
        string memory description,
        ProposalCategory category,
        ProposalType proposalType,
        string[] memory choices,
        bytes memory exectionData,
        address target,
        uint256 value
    ) public virtual nonReentrant returns (uint256) {
        // Access control (e.g., onlyAuthorizedProposer) should be added in the implementation contract.
        require(_activeProposalCount < MAX_ACTIVE_PROPOSALS, "Too many active proposals");
        return _createProposal(title, description, category, proposalType, choices, exectionData, target, value);
    }

    function vote(uint256 proposalId, uint256 choiceIndex) public virtual nonReentrant {
        _vote(msg.sender, proposalId, choiceIndex);
    }

    function resolveProposal(uint256 proposalId) public virtual {
        Proposal storage p = _proposals[proposalId];
        require(p.state == ProposalState.ACTIVE, "Proposal not active");
        require(block.timestamp > p.votingEnd, "Voting still active");
        _resolve(proposalId);
    }

    function executeProposal(uint256 proposalId) public virtual nonReentrant {
        // Access control (e.g., onlyAdmin) should be added in the implementation contract.
        _execute(proposalId);
    }

    function cancelProposal(uint256 proposalId) public virtual {
        // Access control (e.g., onlyAdmin) should be added in the implementation contract.
        _cancel(proposalId);
    }

    // -- Internal Core Functions --

    function _createProposal(
        string memory title,
        string memory description,
        ProposalCategory category,
        ProposalType proposalType,
        string[] memory choices,
        bytes memory executionData,
        address target,
        uint256 value
    ) internal virtual returns (uint256) {}

    function _vote(address voter, uint256 proposalId, uint256 choiceIndex) internal virtual {}

    function _resolve(uint256 proposalId) internal virtual {}

    function _execute(uint256 proposalId) internal virtual {}

    function _cancel(uint256 proposalId) internal virtual {}
}
