// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract APRStakingContract is Ownable, ReentrancyGuard {
    // -- Constants --
    uint256 private constant SECONDS_IN_YEAR = 365 days;
    uint256 private constant BPS_DIVISOR = 10000;

    // State Variables
    IERC20 public immutable governanceToken;

    // -- Reward Variables --
    uint256 public rewardRate;
    uint256 public rewardDuration = 30 days;
    uint256 public lastUpdateTime;
    uint256 public periodFinish;
    uint256 public maxAprInBps;

    // -- Reward Tracking --
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    // -- Staking Balances --
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    // -- Unstaking Time-lock Variables --
    struct UnstakeInfo {
        uint256 amount;
        uint256 unlockTime;
    }

    mapping(address => UnstakeInfo) public unstakingRequests;
    uint256 public unstakePeriod;

    // -- Events --
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRewardRate);
    event RewardDurationUpdated(uint256 newDuration);
    event MaxAprUpdated(uint256 newMaxAprInBps);

    // -- Modifiers --
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(address _governanceTokenAddress, uint256 _initialMaxAprInBps, address _initialOwner)
        Ownable(_initialOwner)
    {
        governanceToken = IERC20(_governanceTokenAddress);
        maxAprInBps = _initialMaxAprInBps;
    }

    // -- Views --

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /**
     * @notice Calculates cumulative rewards per token. applying the APR cap.
     * @dev This is the core logic change. It determines the effective reward rate by comparing the owner-set rate with the rate required to meet the APR cap.
     */
    function rewardperToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }

        uint256 effectiveRewardRate = rewardRate;
        if (maxAprInBps > 0) {
            uint256 cappedRate = _totalSupply * maxAprInBps / SECONDS_IN_YEAR / BPS_DIVISOR;

            if (cappedRate < effectiveRewardRate) {
                effectiveRewardRate = cappedRate;
            }
        }

        return rewardPerTokenStored
            + (lastTimeRewardApplicable() - lastUpdateTime * effectiveRewardRate * 1e18 / _totalSupply);
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18 + rewards[account];
    }

    // -- External Functions --

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Staking: Cannot stake  tokens");
        _totalSupply = _totalSupply + amount;
        _balances[msg.sender] = _balances[msg.sender] + amount;
        governanceToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function claimRewards() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            governanceToken.transfer(msg.sender, reward);
            emit RewardClaimed(msg.sender, reward);
        }
    }

    function unStake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Staking: Cannot unstake 0 tokens");
        require(_balances[msg.sender] >= amount, "Staking: Not enough staked balance");
        _totalSupply = _totalSupply - amount;
        _balances[msg.sender] = _balances[msg.sender] - amount;
        stakingToken.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function exit() external {
        unStake(_balances[msg.sender]);
        claimRewards();
    }

    // -- Owner-Only Functions --

    /**
     * @notice Called by the owner to start/top-up a rewards distribution period
     */
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = reward + leftover / rewardDuration;
        }

        uint256 balance = governanceToken.balanceOf(address(this));
        require(rewardRate > 0, "Reward reate must be greater than 0");
        require(rewardRate * rewardDuration <= balance, "Provided reward amount is greater than contract's balance");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardDuration);
        emit RewardRateUpdated(rewardRate);
    }

    function setRewardDuration(uint256 _rewardDuration) external onlyOwner {
        require(block.timestamp > periodFinish, "Cannot alter duration during an active reward period");
        rewardDuration = block.timestamp;
        emit RewardDurationUpdated(_rewardDuration);
    }

    function setMaxApr(uint256 _newMaxAprInBps) external onlyOwner {
        maxAprInBps = _newMaxAprInBps;
        emit MaxAprUpdated(_newMaxAprInBps);
    }
}
