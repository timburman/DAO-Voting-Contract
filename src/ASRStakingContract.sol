// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract ASRStakingContract is Initializable, ReentrancyGuardUpgradeable, IERC165 {
    IERC20 public stakingToken;
    address public owner;
    uint256 public cooldownPeriod;

    mapping(address => uint256) private _balances;
    uint256 public totalStaked;

    // Voting activity: user => proposalId => votingPowerUsed;
    mapping(address => mapping(uint256 => uint256)) public votingActivity;

    struct UnstakeRequest {
        uint256 amount;
        uint256 requestTime;
        bool claimed;
    }

    mapping(address => UnstakeRequest[]) public unstakeRequests;

    // Events
    event Staked(address indexed user, uint256 amount);
    event UnstakeRequested(address indexed user, uint256 amount, uint256 requestTime, uint256 requestIndex);
    event UnstakeClaimed(address indexed user, uint256 amount, uint256 requestIndex);
    event CooldownPeriodUpdated(uint256 newCooldown);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function initialize(address _stakingToken, uint256 _cooldownPeriod, address _owner) public initializer {
        require(_stakingToken != address(0), "Invalid Token");
        require(_owner != address(0), "Invalid owner");
        require(_cooldownPeriod >= 7 days && _cooldownPeriod <= 30 days, "Cooldown out of range");
        __ReentrancyGuard_init();
        stakingToken = IERC20(_stakingToken);
        cooldownPeriod = _cooldownPeriod;
        owner = _owner;
    }

    // -- Core staking logic --
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer Failed");
        _balances[msg.sender] += amount;
        totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(_balances[msg.sender] >= amount, "Insufficient staked");

        _balances[msg.sender] -= amount;
        totalStaked -= amount;
        unstakeRequests[msg.sender].push(UnstakeRequest({amount: amount, requestTime: block.timestamp, claimed: false}));
        emit UnstakeRequested(msg.sender, amount, block.timestamp, unstakeRequests[msg.sender].length - 1);
    }

    function claimUnstake(uint256 requestIndex) external nonReentrant {
        require(requestIndex < unstakeRequests[msg.sender].length, "Invalid Request");

        UnstakeRequest storage req = unstakeRequests[msg.sender][requestIndex];
        require(!req.claimed, "Already Claimed");
        require(block.timestamp >= req.requestTime + cooldownPeriod, "Cooldown period not passed");

        req.claimed = true;
        require(stakingToken.transfer(msg.sender, req.amount), "Transfer Failed");
        emit UnstakeClaimed(msg.sender, req.amount, requestIndex);
    }

    // -- View Functions --

    function getStakedAmount(address user) external view returns (uint256) {
        return _balances[user];
    }

    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    function getVotingPower(address user) external view returns (uint256) {
        return _balances[user];
    }

    function getUnstakeRequests(address user)
        external
        view
        returns (uint256[] memory amounts, uint256[] memory requestTimes, bool[] memory claimed)
    {
        uint256 len = unstakeRequests[user].length;
        amounts = new uint256[](len);
        requestTimes = new uint256[](len);
        claimed = new bool[](len);

        for (uint256 i = 0; i < len; i++) {
            UnstakeRequest storage req = unstakeRequests[user][i];
            amounts[i] = req.amount;
            requestTimes[i] = req.requestTime;
            claimed[i] = req.claimed;
        }
    }

    // -- Admin Functions --

    function setCooldownPeriod(uint256 newCooldown) external onlyOwner {
        require(newCooldown >= 7 days && newCooldown <= 30 days, "Cooldown out of range");
        emit CooldownPeriodUpdated(newCooldown);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
