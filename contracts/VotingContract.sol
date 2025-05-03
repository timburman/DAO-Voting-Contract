// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./IStakingContract.sol";

/**
 * @title VotingContract
 * @dev Manages DAO Proposals and votes
*/
contract VotingContract is Ownable {
    using SafeMath for uint256;

    IStakingContract public immutable stakingContract;

    enum ProposalState { Pending, Active, Canceled, Defeated, Succeeded}
    enum VoteType { Against, For, Abstain }

    struct ProposalView {
        uint256 id;
        address proposer;
        string description;
        uint256 creationTime;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 totalVotesParticipated;
        uint256 snapshotTotalStaked;
        bool canceled;
        ProposalState state; // Determines the state the proposal is in
        mapping(address => bool) hasVoted; // Tracks if an address has voted on this proposal
        mapping(address => VoteType) voteChoice;
    }

    uint256 public proposalCounter;
    mapping(uint256 => ProposalView) public proposals;

    uint256 public votingPeriod = 5 days; // Duration of voting in seconds
    uint256 public quorumBasisPoints; // Minimum % of total staked power needed

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        uint256 startTime,
        uint256 endTime,
        uint256 snapShotTotalStaked
    );
    event Voted(
        uint256 indexed proposalId,
        address indexed voter,
        VoteType voteType,
        uint256 votingPower
    );
    event ProposalFinished(
        uint256 indexed proposalId,
        ProposalState finalState,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    );
    event ProposalCanceled(uint256 indexed proposalId);


    /**
     * @param _stakingContractAddress Address of the deployed StakingContract.
     * @param _initialQuorumBasisPoints Quorum requirement
     * @param _initialOwner Owner of this contract.
     */
    constructor(
        address _stakingContractAddress,
        uint256 _initialQuorumBasisPoints,
        address _initialOwner
        ) Ownable(_initialOwner) {
        
            require(_stakingContractAddress != address(0), "Staking contract address cannot be zero");
            require(_initialQuorumBasisPoints <= 10000, "Quorum cannot exceed 100%");

            stakingContract = IStakingContract(_stakingContractAddress);
            quorumBasisPoints = _initialQuorumBasisPoints;
    }

    // Proposal

    /**
     * @notice Creates a new proposal.
     * @param _description Text describing the proposal.
     */
    function createProposal(string calldata _description) external onlyOwner returns(uint256) {
        
        proposalCounter = proposalCounter.add(1);
        uint256 proposalId = proposalCounter;

        uint256 currentTime = block.timestamp;
        uint currentTotalStaked = stakingContract.totalStaked();

        ProposalView storage newProposal = proposals[proposalId];
        newProposal.id = proposalId;
        newProposal.proposer = msg.sender;
        newProposal.description = _description;
        newProposal.creationTime = currentTime;
        newProposal.startTime = currentTime;
        newProposal.endTime = currentTime + votingPeriod;
        newProposal.snapshotTotalStaked = currentTotalStaked;
        newProposal.state = ProposalState.Active;

        emit ProposalCreated(proposalId, msg.sender, _description, newProposal.startTime, newProposal.endTime, currentTotalStaked);

        return proposalId;
    }

    /**
     * @notice Allows the proposer to cancel an active proposal.
     * @param _proposalId The ID of the proposal to cancel.
     */
    function cancelProposal(uint256 _proposalId) external onlyOwner{
        ProposalView storage proposal = proposals[_proposalId];
        require(proposal.id != 0, "Proposal Does not exist");
        require(proposal.state == ProposalState.Active, "Proposal Not Active");

        proposal.state = ProposalState.Canceled;
        proposal.canceled = true;

        emit ProposalCanceled(_proposalId);
    }

    // Voting

    /**
     * @notice Allows the users to caste the vote on an active proposal
     * @param _proposalId the proposal Id
     * @param _voteType vote for, against or abstrain
    */
    function casteVote(uint256 _proposalId, VoteType _voteType) external {
        ProposalView storage proposal = proposals[_proposalId];
        require(proposal.id != 0, "Proposal does not exist");
        require(proposal.state == ProposalState.Active, "Proposal is not active");
        require(block.timestamp >= proposal.startTime, "Voting has not started");
        require(block.timestamp < proposal.endTime, "Voting period has ended");
        require(!proposal.hasVoted[msg.sender], "Already voted on this proposal");

        uint256 voterPower = stakingContract.getVotingPower(msg.sender);
        require(voterPower > 0, "Must have staked tokens (voting power) to vote");

        proposal.hasVoted[msg.sender] = true;
        proposal.voteChoice[msg.sender] = _voteType;
        proposal.totalVotesParticipated = proposal.totalVotesParticipated.add(voterPower);

        if (_voteType == VoteType.For) {
            proposal.forVotes = proposal.forVotes.add(voterPower);
        } else if (_voteType == VoteType.Against) {
            proposal.againstVotes = proposal.againstVotes.add(voterPower);
        } else if (_voteType == VoteType.Abstain) {
            proposal.abstainVotes = proposal.abstainVotes.add(voterPower);
        } else {
            revert("Invalid vote type");
        }

        emit Voted(_proposalId, msg.sender, _voteType, voterPower);
    }

    // Finishing of Proposal

    /**
     * @notice Allows everyone to finish the proposal after its voting period is over
     * @param _proposalId the proposal id
    */
    function finishProposal(uint256 _proposalId) external {
        ProposalView storage proposal = proposals[_proposalId];
        require(proposal.id != 0, "Proposal does not exist");
        require(proposal.state == ProposalState.Active, "Proposal is not active or already finished");
        require(block.timestamp >= proposal.endTime, "Voting period not yet over");

        bool quorumReached = false;
        if (proposal.snapshotTotalStaked > 0) {
            uint256 participationBasisPoints = proposal.totalVotesParticipated.mul(10000).div(proposal.snapshotTotalStaked);
            if (participationBasisPoints >= quorumBasisPoints) {
                quorumReached = true;
            }
        }

        if (!quorumReached) {
            proposal.state = ProposalState.Defeated;
        } else {
            if (proposal.forVotes > proposal.againstVotes) {
                proposal.state = ProposalState.Succeeded;
            } else {
                proposal.state = ProposalState.Defeated;
            }
        }

        emit ProposalFinished(
            _proposalId,
            proposal.state,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.abstainVotes
        );
    }

    // View functions


    /**
     * @notice Fetches the proposal using proposalId
     * @param _proposalId proposal id to fetch
    */
    function getProposal(uint256 _proposalId) external view
    returns(
        uint256 id,
        address proposer,
        string memory description,
        uint256 startTime,
        uint256 endTime,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes,
        uint256 totalVotesParticipated,
        uint256 snapshotTotalStaked,
        bool canceled,
        ProposalState state
        )
    {
        ProposalView storage proposal = proposals[_proposalId];
        require(proposal.id != 0, "Proposal does not exist");
        return (
            proposal.id,
            proposal.proposer,
            proposal.description,
            proposal.startTime,
            proposal.endTime,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.abstainVotes,
            proposal.totalVotesParticipated,
            proposal.snapshotTotalStaked,
            proposal.canceled,
            proposal.state
        );
    }


    /**
     * @notice 
    */
    function getVote(uint256 _proposalId, address _voter) external view returns (bool hasVoted, VoteType voteChoice) {
        ProposalView storage proposal = proposals[_proposalId];
         require(proposal.id != 0, "Proposal does not exist");
        return (proposal.hasVoted[_voter], proposal.voteChoice[_voter]);
    }

    // Maintainance Funtions or Admin Functions

    function setVotingPeriod(uint256 _newVotingPeriod) external onlyOwner {
        require(_newVotingPeriod > 0, "Voting period must be positive");
        votingPeriod = _newVotingPeriod;
    }

    function setQuorum(uint256 _newQuorumBasisPoints) external onlyOwner {
        require(_newQuorumBasisPoints <= 10000, "Quorum cannot exceed 100%");
        quorumBasisPoints = _newQuorumBasisPoints;
    }


}