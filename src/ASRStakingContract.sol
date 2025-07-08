// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract ASRStakingContract is Initializable, ReentrancyGuardUpgradeable, IERC165 {
    // -- Stake Variables --
    IERC20 public stakingToken;
    address public owner;
    address public pendingOwner;
    uint256 public cooldownPeriod;
    uint256 public minimumStakeAmount;
    uint256 public minimumUnstakeAmount;
    bool public emergencyMode;

    uint256 public constant MAX_UNSTAKE_REQUESTS = 3;
    uint256 public constant MIN_COOLDOWN = 7 days;
    uint256 public constant MAX_COOLDOWN = 30 days;

    mapping(address => uint256) private _balances;
    uint256 public totalStaked;

    // Unstake Requests
    struct UnstakeRequest {
        uint256 amount;
        uint256 requestTime;
    }

    mapping(address => UnstakeRequest[]) public unstakeRequests;

    // -- Events --
    event Staked(address indexed user, uint256 amount, uint256 newTotalStaked, uint256 newUserBalance);

    event UnstakeRequested(
        address indexed user, uint256 amount, uint256 requestTime, uint256 requestIndex, uint256 claimableAt
    );

    event UnstakeClaimed(address indexed user, uint256 amount, uint256 requestIndex);

    event BatchUnstakeClaimed(address indexed user, uint256 totalAmount, uint256 requestCount);

    event CooldownPeriodUpdated(uint256 newCooldown);
    event MinimumAmountUpdated(uint256 minStake, uint256 minUnstake);
    event EmergencyModeUpdated(bool enabled);
    event OwnershipTransferred(address indexed previosOwner, address indexed newOwner);

    // -- Mofifier --
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // -- Initialization --
    function initialize(address _stakingToken, uint256 _cooldownPeriod, address _owner) public initializer {
        require(_stakingToken != address(0), "Invalid Token");
        require(_owner != address(0), "Invalid owner");
        require(_cooldownPeriod >= MIN_COOLDOWN && _cooldownPeriod <= MAX_COOLDOWN, "Cooldown out of range");

        __ReentrancyGuard_init();

        stakingToken = IERC20(_stakingToken);
        cooldownPeriod = _cooldownPeriod;
        owner = _owner;
        minimumStakeAmount = 1;
        minimumUnstakeAmount = 1;
        emergencyMode = false;
    }

    // -- Core Staking Logic --
    function stake(uint256 amount) external nonReentrant {
        require(amount >= minimumStakeAmount, "Amount below minimum");
        require(stakingToken.balanceOf(msg.sender) >= amount, "Insufficient token balalnce");
        require(stakingToken.allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");

        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        _balances[msg.sender] += amount;
        totalStaked += amount;

        emit Staked(msg.sender, amount, totalStaked, _balances[msg.sender]);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(amount >= minimumUnstakeAmount, "Amount below minimum");
        require(_balances[msg.sender] >= amount, "Insufficient staked");
        require(unstakeRequests[msg.sender].length < MAX_UNSTAKE_REQUESTS, "Max unstake requess reached");

        _balances[msg.sender] -= amount;
        totalStaked -= amount;

        unstakeRequests[msg.sender].push(UnstakeRequest({amount: amount, requestTime: block.timestamp}));

        uint256 requestIndex = unstakeRequests[msg.sender].length - 1;
        uint256 claimableAt = block.timestamp + cooldownPeriod;

        emit UnstakeRequested(msg.sender, amount, block.timestamp, requestIndex, claimableAt);
    }

    function claimUnstake(uint256 requestIndex) external nonReentrant {
        require(requestIndex < unstakeRequests[msg.sender].length, "Invalid request");

        UnstakeRequest storage req = unstakeRequests[msg.sender][requestIndex];

        if (!emergencyMode) {
            require(block.timestamp >= req.requestTime + cooldownPeriod, "Cooldown not passed");
        }

        uint256 amount = req.amount;

        _removeRequestByIndex(msg.sender, requestIndex);

        require(stakingToken.transfer(msg.sender, amount), "Transfer failed");

        emit UnstakeClaimed(msg.sender, amount, requestIndex);
    }

    function claimAllReady() external nonReentrant {
        UnstakeRequest[] storage requests = unstakeRequests[msg.sender];
        require(requests.length > 0, "No unstake requessts");

        uint256 totalAmount = 0;
        uint256 claimedCount = 0;

        for (int256 i = int256(requests.length) - 1; i >= 0; i--) {
            UnstakeRequest storage req = requests[uint256(i)];

            bool canClaim = emergencyMode || (block.timestamp >= req.requestTime + cooldownPeriod);

            if (canClaim) {
                totalAmount += req.amount;
                claimedCount++;

                _removeRequestByIndex(msg.sender, uint256(i));
            }
        }

        require(totalAmount > 0, "No Claimable requests");
        require(stakingToken.transfer(msg.sender, totalAmount), "Transfer failed");

        emit BatchUnstakeClaimed(msg.sender, totalAmount, claimedCount);
    }

    // -- Internal Helper Functions --
    function _removeRequestByIndex(address user, uint256 index) internal {
        UnstakeRequest[] storage requests = unstakeRequests[user];
        require(index < requests.length, "Invalid index");

        requests[index] = requests[requests.length - 1];
        requests.pop();
    }

    //  -- View Functions --
    function getStakedAmount(address user) external view returns (uint256) {
        return _balances[user];
    }

    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    function getVotingPower(address user) external view returns (uint256) {
        return _balances[user];
    }

    function getUnstakeRequests(address user, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory amounts, uint256[] memory requestTimes, bool[] memory claimed)
    {}

    // -- Interface Support --
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
