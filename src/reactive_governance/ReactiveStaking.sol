// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract ReactiveStaking is ReentrancyGuardUpgradeable {
    // -- State Variables --

    /// @notice The ERC20 token for staking
    IERC20 internal stakingToken;
    /// @notice The address of VotingContract, only authorized contract to manage proposals
    address internal _votingContract;

    // -- Staking Balances --
    mapping(address => uint256) private _balances;
    uint256 private _totalStaked;

    // -- Config --
    uint256 internal _cooldownPeriod;
    uint256 internal _minimumStakeAmount;
    uint256 internal _minimumUnstakeAmount;
    bool internal _emergencyMode;

    // -- Constants --
    uint256 public constant MAX_UNSTAKE_REQUESTS = 3;
    uint256 public constant MIN_COOLDOWN = 7 days;
    uint256 public constant MAX_COOLDOWN = 30 days;

    // -- Proposal State --
    bool internal _isProposalActive;
    uint256 internal _currentProposalPeriod;
    uint256 internal _activeProposalCount;
    uint256 internal _totalProposalCount;
    uint256 public constant MAX_ACTIVE_PROPOSAL = 3;
    uint256[] internal _activeProposalIds;
    mapping(uint256 => uint256) internal _activeProposalIndex;

    // -- Structs --
    struct UnstakeRequest {
        uint256 amount;
        uint256 requestTime;
    }

    struct ProposalDetails {
        bool active;
        uint256 reserved; // For Potential future use
    }

    // -- Mappings --
    mapping(uint256 => ProposalDetails) internal _proposalDetails;
    mapping(address => UnstakeRequest[]) internal _unstakeRequests;
    mapping(address => mapping(uint256 => uint256)) internal _preProposalBalance;
    mapping(address => mapping(uint256 => bool)) internal _userSnapshotTaken;

    // -- Events --
    event Staked(address indexed user, uint256 amount, uint256 newTotalStaked, uint256 newUserBalance);
    event UnstakeRequested(
        address indexed user, uint256 amount, uint256 requestTime, uint256 requestIndex, uint256 claimableAt
    );
    event UnstakeClaimed(address indexed user, uint256 amount, uint256 requestIndex);
    event BatchUnstakeClaimed(address indexed user, uint256 totalAmount, uint256 requestCount);
    event ProposalCreated(uint256 indexed proposalId);
    event ProposalEnded(uint256 indexed proposalId);
    event UserSnapshottedForProposal(address indexed user, uint256 balance, uint256 indexed proposalId);
    event VotingContractUpdated(address indexed newVotingContract);

    // -- Modifiers --
    modifier onlyVotingContract() {
        require(msg.sender == _votingContract, "Only Voting Contract");
        _;
    }

    /**
     * @dev Initializes the contract. To be called from the child contact's initializer
     */
    function _initializeReactiveStaking(
        address stakingTokenAddress,
        uint256 cooldown,
        uint256 minStake,
        uint256 minUnstake
    ) internal {
        require(stakingTokenAddress != address(0), "Invalid Token");
        require(cooldown >= MIN_COOLDOWN && cooldown <= MAX_COOLDOWN, "Cooldown out of range");
        __ReentrancyGuard_init();
        stakingToken = IERC20(stakingTokenAddress);
        _cooldownPeriod = cooldown;
        _minimumStakeAmount = minStake;
        _minimumUnstakeAmount = minUnstake;
    }

    // -- Staking Functions --
}
