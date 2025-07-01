// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FixedAPRStakingContract
 * @notice A Staking contract with fixed periods and scaled APR rates
 * @dev Multiple stake periods available, auto-unlock after completion, proxy-upgradeable ready
 */
contract FixedAPRStakingContract is Ownable, ReentrancyGuard {
    IERC20 public immutable governanceToken;

    // -- Constants --
    uint256 public constant MAX_APR = 5000;
    uint256 public constant BPS_DIVISOR = 10000;
    uint256 public constant APR_CHANGE_COOLDOWN = 7 days;
    uint256 public constant MIN_AUTO_COMPOUND_AMOUNT = 0.01 ether;

    // -- Stake periods configuration --
    struct StakePeriodConfig {
        uint256 durationInDays;
        bool active;
        uint256 scaledAPR;
    }

    struct UserStake {
        uint256 amount;
        uint256 stakedAt;
        uint256 unlockTime;
        uint256 stakePeriodDays;
        uint256 aprInBps;
        uint256 lastClaimTime;
        uint256 reservedReward;
        bool autoCompound;
        bool active;
        bool withdrawn;
        uint8 periodIndex;
    }

    struct RewardPool {
        uint256 totalFunded;
        uint256 totalReserved;
        uint256 baseAPRFor365Days;
        uint256 lastAPRChange;
        bool fundsAvailable;
    }

    // Reward pool management
    StakePeriodConfig[] public stakePeriods;
    mapping(address => UserStake[]) public userStakes;
    RewardPool public rewardPool;
    uint256 public totalStaked;

    event Staked(
        address indexed user,
        uint256 amount,
        uint256 aprInBps,
        uint256 stakeIndex,
        uint256 unlockTime,
        uint8 periodIndex,
        bool autoCompound
    );
    event RewardsClaimed(address indexed user, uint256 amount, uint256 stakeIndex, bool autoCompound);
    event Withdrawn(address indexed user, uint256 amount, uint256 stakeIndex, uint256 rewards);
    event Restaked(address indexed user, uint256 stakeIndex, uint256 newStakeIndex, uint8 newPeriodIndex);
    event BaseAPRUpdated(uint256 newBaseAPR);
    event StakePeriodToggled(uint8 periodIndex, bool active);
    event AutoCompoundToggled(address indexed user, uint256 stakeIndex, bool enabled);
    event RewardPoolFunded(uint256 amount);
    event ExcessFundsWithdrawn(uint256 amount);

    constructor(address _governanceToken) Ownable(msg.sender) {
        governanceToken = IERC20(_governanceToken);
    }
}
