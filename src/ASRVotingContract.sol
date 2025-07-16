// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    IERC20 public asrToken;

    // -- AUTHORIZATION --
    mapping(address => bool) public authorizedAdmins;
    uint256 public adminCount;
    mapping(address => bool) public authorizedProposers;

    address public safeAddress;

    // Quaterly periods
    uint256 public currentQuarter;
    uint256 public constant QUARTER_DURATION = 90 days;
    uint256 public quarterStartTime;

    // ASR pools and distribution
    mapping(uint256 => uint256) public quarterASRPool;
    mapping(uint256 => bool) public quarterDistributed;
    mapping(uint256 => uint256) public quarterTotalVotingPower;

    // User quarterly voting tracking
    mapping(address => mapping(uint256 => uint256)) public userQuarterVotingPower;
    mapping(address => mapping(uint256 => bool)) public userQuarterClaimed;

    //  Proposal to quarter mapping
    mapping(uint256 => uint256) public proposalQuarter;

    // ASR Claim deadline system
    uint256 public constant CLAIM_DEADLINE = 30 days;
    mapping(uint256 => uint256) public quarterClaimDeadline;
    mapping(uint256 => bool) public quarterAsrFunded;
    mapping(uint256 => uint256) public quarterClaimedAmount;
    bool public proposalCreationEnabled;

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

    event VoteCast(address indexed voter, uint256 indexed proposalId, uint256 choiceIndex, uint256 votingPower);

    event ProposalCancelled(uint256 indexed proposalId, address indexed canceller);

    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);

    event ProposalResolved(uint256 proposalId, ProposalState state, uint256 choiceIndex);
    event ProposerAdded(address indexed proposer);
    event ProposerRemoved(address indexed proposer);
    event ProposerManagerUpdated(address indexed newManager);
    event CategoryRequirementsUpdated(ProposalCategory indexed category);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    event SafeExecutionAttempted(address target, uint256 value, bytes data);
    event AdminAdded(address indexed newAdmin);
    event AdminRemoved(address indexed admin);
    event SafeAddressUpdated(address indexed safeAddress);

    event AsrTokenSet(address indexed asrToken);
    event QuarterStarted(uint256 indexed quarter);
    event QuarterAsrSet(uint256 indexed quarter, uint256 asrAmount);
    event QuarterFinalized(uint256 indexed quarter, uint256 asrPool, uint256 claimDeadline);
    event AsrRewardsClaimed(address indexed user, uint256[] quarters, uint256 totalAsrReward);
    event UnclaimedAsrRecovered(uint256 indexed quarter, uint256 amount);

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
    function initialize(address _stakingContract, address _proposalManager, address _asrToken, address _owner)
        public
        initializer
    {
        require(_stakingContract != address(0), "ASRVotingContract: Staking contract address cannot be zero");
        require(_proposalManager != address(0), "ASRVotingContract: Proposal manager address cannot be zero");
        require(_owner != address(0), "ASRVotingContract: Owner address cannot be zero");
        require(_asrToken != address(0), "Invalid ASR token");

        __ReentrancyGuard_init();

        stakingContract = ASRStakingContract(_stakingContract);
        proposalManager = _proposalManager;
        owner = _owner;
        activeProposalCount = 0;
        adminCount = 0;
        currentQuarter = 0;
        quarterStartTime = 0;
        proposalCreationEnabled = false;

        asrToken = IERC20(_asrToken);

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
        require(proposalCreationEnabled, "Proposal creation disabled - ASR not funded");
        require(quarterAsrFunded[currentQuarter], "Current quarter not funded");
        require(currentQuarter > 0, "No active quarter");

        if (proposalType == ProposalType.BINARY) {
            require(choices.length == 0, "Binary proposals don't need choices");
        } else {
            require(choices.length > 2 && choices.length <= 10, "Invalid choice count");
        }

        proposalCounter++;
        uint256 proposalId = proposalCounter;
        proposalQuarter[proposalId] = getCurrentQuarter();

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
    function vote(uint256 proposalId, uint256 choiceIndex) external proposalExists(proposalId) nonReentrant {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.state == ProposalState.ACTIVE, "Proposal not active");
        require(
            block.timestamp <= proposal.votingEnd && block.timestamp >= proposal.creationTime, "Voting period ended"
        );
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(choiceIndex < proposal.choices.length, "Invalid choice");

        uint256 votingPower = stakingContract.getVotingPowerForProposal(msg.sender, proposalId);
        require(votingPower > 0, "No voting power");

        proposal.hasVoted[msg.sender] = true;
        proposal.userVote[msg.sender] = choiceIndex;
        proposal.voteCounts[choiceIndex] += votingPower;
        proposal.totalVotes += votingPower;

        _trackAsrVoting(msg.sender, proposalId, votingPower);

        emit VoteCast(msg.sender, proposalId, choiceIndex, votingPower);
    }

    function _trackAsrVoting(address user, uint256 proposalId, uint256 votingPower) internal {
        uint256 quarter = getCurrentQuarter();
        require(quarter > 0, "No active quarter");
        require(proposalQuarter[proposalId] == quarter, "Proposal not in the quarter");

        userQuarterVotingPower[user][quarter] += votingPower;

        quarterTotalVotingPower[quarter] += votingPower;

        // if (proposalQuarter[proposalId] != quarter) {
        //     proposalQuarter[proposalId] = quarter;
        // }
    }

    function calculateAsrReward(address user, uint256 quarter) public view returns (uint256 asrReward) {
        if (quarterTotalVotingPower[quarter] == 0) return 0;
        if (!quarterAsrFunded[quarter]) return 0;

        uint256 userVotingPower = userQuarterVotingPower[user][quarter];
        uint256 totalVotingPower = quarterTotalVotingPower[quarter];
        uint256 asrPool = quarterASRPool[quarter];

        asrReward = (userVotingPower * asrPool) / totalVotingPower;
    }

    function claimAsrRewards(uint256[] memory quarters) external nonReentrant {
        uint256 totalAsrReward = 0;

        for (uint256 i = 0; i < quarters.length; i++) {
            uint256 quarter = quarters[i];

            require(quarter < getCurrentQuarter(), "Quarter not completed");
            require(quarterDistributed[quarter], "Quarter not distributed");
            require(!userQuarterClaimed[msg.sender][quarter], "Already claimed");
            require(block.timestamp <= quarterClaimDeadline[quarter], "Claim deadline passed");

            uint256 asrReward = calculateAsrReward(msg.sender, quarter);
            if (asrReward > 0) {
                userQuarterClaimed[msg.sender][quarter] = true;
                quarterClaimedAmount[quarter] += asrReward;
                totalAsrReward += asrReward;
            }
        }

        if (totalAsrReward > 0) {
            asrToken.approve(address(stakingContract), totalAsrReward);
            stakingContract.addAsrRewards(msg.sender, totalAsrReward);
            emit AsrRewardsClaimed(msg.sender, quarters, totalAsrReward);
        }
    }

    function resolveProposal(uint256 proposalId) external proposalExists(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.state == ProposalState.ACTIVE, "Proposal not active");
        require(block.timestamp > proposal.votingEnd, "Voting still active");

        _resolveProposal(proposalId);
    }

    function _resolveProposal(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];

        stakingContract.endProposal(proposalId);
        activeProposalCount--;

        uint256 totalStaked = stakingContract.totalStaked();
        uint256 quorumRequired = (totalStaked * proposal.quorumRequired) / 10000;

        bool quorumMet = proposal.totalVotes >= quorumRequired;

        if (!quorumMet) {
            proposal.state = ProposalState.DEFEATED;
            emit ProposalResolved(proposalId, ProposalState.DEFEATED, 0);
            return;
        }
        if (proposal.proposalType == ProposalType.BINARY) {
            uint256 forVotes = proposal.voteCounts[0];
            uint256 againstVotes = proposal.voteCounts[1];
            uint256 abstrainVotes = proposal.voteCounts[2];
            uint256 totalCastedVotes = forVotes + againstVotes + abstrainVotes;

            uint256 approvalRequired = (totalCastedVotes * proposal.approvalRequired) / 10000;

            if (forVotes >= approvalRequired) {
                proposal.state = ProposalState.SUCCEEDED;
                emit ProposalResolved(proposalId, ProposalState.SUCCEEDED, 0);
            } else {
                proposal.state = ProposalState.DEFEATED;
                emit ProposalResolved(proposalId, ProposalState.DEFEATED, againstVotes > abstrainVotes ? 1 : 2);
            }
        } else {
            uint256 winningChoice = 0;
            uint256 maxVotes = proposal.voteCounts[0];

            for (uint256 i = 1; i < proposal.voteCounts.length; i++) {
                if (proposal.voteCounts[i] > maxVotes) {
                    maxVotes = proposal.voteCounts[i];
                    winningChoice = i;
                }
            }

            proposal.state = ProposalState.SUCCEEDED;
            emit ProposalResolved(proposalId, ProposalState.SUCCEEDED, winningChoice);
        }
    }

    function executeProposal(uint256 proposalId) external proposalExists(proposalId) onlyAuthorizedAdmin {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.state == ProposalState.SUCCEEDED, "Proposal not passed");
        require(block.timestamp >= proposal.executionTime, "Execution deplay not met");
        require(block.timestamp <= proposal.gracePeriodEnd, "Grace period expired");

        proposal.state = ProposalState.EXECUTED;

        if (safeAddress != address(0) && proposal.exectionData.length > 0) {
            _executeViaSafe(proposal.target, proposal.value, proposal.exectionData);
        }

        emit ProposalExecuted(proposalId, msg.sender);
    }

    function _executeViaSafe(address target, uint256 value, bytes memory data) internal {
        require(safeAddress != address(0), "Safe not configured");
        // =============================================
        // =============== Place holder ================
        // =============================================
        emit SafeExecutionAttempted(target, value, data);
    }

    function startNewQuarter() external onlyAuthorizedAdmin {
        if (currentQuarter > 0) {
            require(block.timestamp >= quarterStartTime + QUARTER_DURATION, "Quarter not ended");
            require(activeProposalCount == 0, "Previous quarter proposal still active");

            quarterDistributed[currentQuarter] = true;
            quarterClaimDeadline[currentQuarter] = block.timestamp + CLAIM_DEADLINE;

            emit QuarterFinalized(currentQuarter, quarterASRPool[currentQuarter], quarterClaimDeadline[currentQuarter]);
        }

        currentQuarter++;
        quarterStartTime = block.timestamp;
        proposalCreationEnabled = false;

        emit QuarterStarted(currentQuarter);
    }

    // -- Admin Functions --

    function addAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid admin");
        require(!authorizedAdmins[newAdmin], "Already admin");

        authorizedAdmins[newAdmin] = true;
        adminCount++;

        emit AdminAdded(newAdmin);
    }

    function removeAdmin(address admin) external onlyOwner {
        require(authorizedAdmins[admin], "Not an admin");
        require(adminCount > 1, "Cannot remove last admin");

        authorizedAdmins[admin] = false;
        adminCount--;

        emit AdminRemoved(admin);
    }

    function setSafeAddress(address _safeAddress) external onlyOwner {
        safeAddress = _safeAddress;
        emit SafeAddressUpdated(_safeAddress);
    }

    function addAuthorizedProposer(address proposer) external onlyAuthorizedAdmin {
        require(proposer != address(0), "Invalid proposer");
        authorizedProposers[proposer] = true;
        emit ProposerAdded(proposer);
    }

    function removeAuthorizedProposer(address proposer) external onlyAuthorizedAdmin {
        authorizedProposers[proposer] = false;
        emit ProposerRemoved(proposer);
    }

    function cancelProposal(uint256 proposalId) external proposalExists(proposalId) onlyAuthorizedAdmin {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.state == ProposalState.ACTIVE, "Proposal not active");

        proposal.state = ProposalState.CANCELLED;

        // End proposal in staking contract
        stakingContract.endProposal(proposalId);
        activeProposalCount--;

        emit ProposalCancelled(proposalId, msg.sender);
    }

    function setQuarterAsrAndFund(uint256 quarter, uint256 asrAmount) external onlyOwner {
        require(quarter > 0, "Invalid quarter");
        require(asrAmount > 0, "Invalid ASR amount");
        require(!quarterAsrFunded[quarter], "Quarter already funded");
        require(address(asrToken) != address(0), "ASR token not set");
        require(asrToken.balanceOf(msg.sender) >= asrAmount, "Not enough tokens in account");
        require(asrToken.allowance(msg.sender, address(this)) >= asrAmount, "Aproval amount not sufficient");

        require(asrToken.transferFrom(msg.sender, address(this), asrAmount), "Asr transfer failed");

        quarterASRPool[quarter] = asrAmount;
        quarterAsrFunded[quarter] = true;

        if (quarter == currentQuarter) {
            proposalCreationEnabled = true;
        }

        emit QuarterAsrSet(quarter, asrAmount);
    }

    function recoverUncalimedAsr(uint256 quarter) external onlyOwner {
        require(quarter < getCurrentQuarter(), "Quarter not completed");
        require(quarterDistributed[quarter], "Quarter not distributed");
        require(block.timestamp > quarterClaimDeadline[quarter], "Claim period not ended");

        uint256 totalAsrPool = quarterASRPool[quarter];
        uint256 claimedAmount = quarterClaimedAmount[quarter];
        uint256 unclaimedAmount = totalAsrPool - claimedAmount;

        if (unclaimedAmount > 0) {
            require(asrToken.transfer(msg.sender, unclaimedAmount), "Recovery transfer failed");
            emit UnclaimedAsrRecovered(quarter, unclaimedAmount);
        }
    }

    // -- View functions --
    function getProposalDetails(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (
            string memory title,
            string memory description,
            address proposer,
            ProposalState state,
            uint256 votingEnd,
            uint256 totalVotes,
            string[] memory choices,
            uint256[] memory voteCounts
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.title,
            proposal.description,
            proposal.proposer,
            proposal.state,
            proposal.votingEnd,
            proposal.totalVotes,
            proposal.choices,
            proposal.voteCounts
        );
    }

    function getUserVoteInfo(uint256 proposalId, address user)
        external
        view
        proposalExists(proposalId)
        returns (bool hasVoted, uint256 votedChoice, uint256 votingPower)
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.hasVoted[user],
            proposal.userVote[user],
            stakingContract.getVotingPowerForProposal(user, proposalId)
        );
    }

    function getActiveProposals() external view returns (uint256[] memory activeIds) {
        uint256[] memory tempIds = new uint256[](proposalCounter);
        uint256 count = 0;

        for (uint256 i = 1; i <= proposalCounter; i++) {
            if (proposals[i].state == ProposalState.ACTIVE) {
                tempIds[count] = i;
                count++;
            }
        }

        activeIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            activeIds[i] = tempIds[i];
        }
    }

    function getProposalsByState(ProposalState state) external view returns (uint256[] memory proposalIds) {
        uint256[] memory tempIds = new uint256[](proposalCounter);
        uint256 count = 0;

        for (uint256 i = 1; i <= proposalCounter; i++) {
            if (proposals[i].state == state) {
                tempIds[count] = i;
                count++;
            }
        }

        proposalIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            proposalIds[i] = tempIds[i];
        }
    }

    function getCurrentQuarter() public view returns (uint256) {
        return currentQuarter;
    }

    function canUserClaim(address user, uint256 quarter)
        external
        view
        returns (bool canClaim, string memory reason, uint256 asrAmount, uint256 deadline)
    {
        if (quarter >= getCurrentQuarter()) {
            return (false, "Quarter not completed", 0, 0);
        }

        if (!quarterDistributed[quarter]) {
            return (false, "Quarter not distributed", 0, 0);
        }

        if (userQuarterClaimed[user][quarter]) {
            return (false, "Already claimed", 0, 0);
        }

        if (block.timestamp > quarterClaimDeadline[quarter]) {
            return (false, "Claim deadline passed", 0, quarterClaimDeadline[quarter]);
        }

        uint256 asrReward = calculateAsrReward(user, quarter);
        return (true, "Can claim", asrReward, quarterClaimDeadline[quarter]);
    }

    /**
     * @dev Get quarter status
     */
    function getQuarterStatus(uint256 quarter)
        external
        view
        returns (
            bool funded,
            bool distributed,
            uint256 asrPool,
            uint256 claimDeadline,
            bool claimActive,
            uint256 totalVotingPower
        )
    {
        funded = quarterAsrFunded[quarter];
        distributed = quarterDistributed[quarter];
        asrPool = quarterASRPool[quarter];
        claimDeadline = quarterClaimDeadline[quarter];
        claimActive = distributed && block.timestamp <= claimDeadline;
        totalVotingPower = quarterTotalVotingPower[quarter];
    }

    /**
     * @dev Get user's ASR info for multiple quarters
     */
    function getUserAsrInfo(address user, uint256[] memory quarters)
        external
        view
        returns (
            uint256[] memory votingPowers,
            uint256[] memory asrRewards,
            bool[] memory claimed,
            bool[] memory canClaim
        )
    {
        votingPowers = new uint256[](quarters.length);
        asrRewards = new uint256[](quarters.length);
        claimed = new bool[](quarters.length);
        canClaim = new bool[](quarters.length);

        for (uint256 i = 0; i < quarters.length; i++) {
            uint256 quarter = quarters[i];
            votingPowers[i] = userQuarterVotingPower[user][quarter];
            asrRewards[i] = calculateAsrReward(user, quarter);
            claimed[i] = userQuarterClaimed[user][quarter];

            canClaim[i] = quarter < getCurrentQuarter() && quarterDistributed[quarter] && !claimed[i]
                && block.timestamp <= quarterClaimDeadline[quarter];
        }
    }

    // -- Interface Support --
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
