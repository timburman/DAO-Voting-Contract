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
    event UnstakeInitiated(address indexed user, uint256 amount, uint256 unlockTime);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRewardRate);
    event RewardDurationUpdated(uint256 newDuration);
    event MaxAprUpdated(uint256 newMaxAprInBps);
    event UnstakePeriodUpdated(uint256 newPeriod);

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

    constructor(
        address _governanceTokenAddress,
        uint256 _initialMaxAprInBps,
        uint256 _initialUnstakePeriod,
        address _initialOwner
    ) Ownable(_initialOwner) {
        governanceToken = IERC20(_governanceTokenAddress);
        maxAprInBps = _initialMaxAprInBps;
        unstakePeriod = _initialUnstakePeriod;
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

    function getAvailableRewardBalance() external view returns (uint256) {
        uint256 totalBalance = governanceToken.balanceOf(address(this));
        return totalBalance > _totalSupply ? totalBalance - _totalSupply : 0;
    }

    /**
     * @notice Calculates cumulative rewards per token. applying the APR cap.
     * @dev This is the core logic change. It determines the effective reward rate by comparing the owner-set rate with the rate required to meet the APR cap.
     */
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }

        uint256 effectiveRewardRate = rewardRate;
        if (maxAprInBps > 0) {
            uint256 cappedRate = (_totalSupply * maxAprInBps) / SECONDS_IN_YEAR / BPS_DIVISOR;

            if (cappedRate < effectiveRewardRate) {
                effectiveRewardRate = cappedRate;
            }
        }

        return rewardPerTokenStored
            + ((lastTimeRewardApplicable() - lastUpdateTime) * effectiveRewardRate * 1e18) / _totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        return (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    // -- External Functions --

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Staking: Cannot stake 0 tokens");
        unchecked {
            _totalSupply = _totalSupply + amount;
            _balances[msg.sender] = _balances[msg.sender] + amount;
        }
        require(governanceToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
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

    function initiateUnstake(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Staking: Cannot unstake 0 tokens");
        require(_balances[msg.sender] >= amount, "Staking: Insufficient balance");
        require(unstakingRequests[msg.sender].amount == 0, "Staking: Unstake request already in progress");

        _totalSupply = _totalSupply - amount;
        _balances[msg.sender] = _balances[msg.sender] - amount;

        uint256 unlockTime = block.timestamp + unstakePeriod;
        unstakingRequests[msg.sender] = UnstakeInfo({amount: amount, unlockTime: unlockTime});

        emit UnstakeInitiated(msg.sender, amount, unlockTime);
    }

    function withdraw() external nonReentrant {
        UnstakeInfo storage request = unstakingRequests[msg.sender];
        require(request.amount > 0, "Withdraw: No unstake request found");
        require(block.timestamp >= request.unlockTime, "Withdraw: Unstake period not yet over");

        uint256 amountToWithdraw = request.amount;

        delete unstakingRequests[msg.sender];

        governanceToken.transfer(msg.sender, amountToWithdraw);
        emit Withdrawn(msg.sender, amountToWithdraw);
    }

    function exit() external {
        claimRewards();

        uint256 balance = _balances[msg.sender];
        if (balance > 0) {
            initiateUnstake(balance);
        }
    }

    // -- Owner-Only Functions --

    /**
     * @notice Called by the owner to start/top-up a rewards distribution period
     * @dev Owner must transfer the reward tokens to this contract before calling this function.
     */
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        require(reward > 0, "Reward amount must be greater than 0");

        uint256 allowance = governanceToken.allowance(msg.sender, address(this));
        require(allowance >= reward, "Insufficient token allowance");

        uint256 balanceBefore = governanceToken.balanceOf(address(this));

        governanceToken.transferFrom(msg.sender, address(this), reward);

        uint256 balanceAfter = governanceToken.balanceOf(address(this));
        require(balanceAfter >= balanceBefore + reward, "Token transfer failed or insufficient balance");

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardDuration;
        }

        require(rewardRate > 0, "Reward reate must be greater than 0");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardDuration;
        emit RewardRateUpdated(rewardRate);
    }

    function setRewardDuration(uint256 _rewardDuration) external onlyOwner {
        require(block.timestamp > periodFinish, "Cannot alter duration during an active reward period");
        rewardDuration = _rewardDuration;
        emit RewardDurationUpdated(_rewardDuration);
    }

    function setMaxApr(uint256 _newMaxAprInBps) external onlyOwner {
        require(_newMaxAprInBps <= BPS_DIVISOR, "APR exceeds 100%");
        maxAprInBps = _newMaxAprInBps;
        emit MaxAprUpdated(_newMaxAprInBps);
    }

    function setUnstakePeriod(uint256 _newPeriod) external onlyOwner {
        require(_newPeriod <= 30 days, "Unstake period cannot be more than 30 days");
        unstakePeriod = _newPeriod;
        emit UnstakePeriodUpdated(_newPeriod);
    }
}
