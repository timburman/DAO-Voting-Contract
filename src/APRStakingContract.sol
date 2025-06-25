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
    uint256 public rewardDuration;
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

    // -- Events --
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRewardRate);
    event RewardDurationUpdated(uint256 newDuration);
    event MaxAprUpdated(uint256 newMaxAprInBps);

    constructor(address _governanceTokenAddress, uint256 _initialMaxAprInBps, address _initialOwner)
        Ownable(_initialOwner)
    {
        governanceToken = IERC20(_governanceTokenAddress);
        maxAprInBps = _initialMaxAprInBps;
    }
}
