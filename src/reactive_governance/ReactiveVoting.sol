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
}
