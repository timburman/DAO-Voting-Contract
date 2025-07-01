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

    // Constants
    uint256 public constant MAX_APR = 5000;
    uint256 public constant BPS_DIVISOR = 10000;
    uint256 public constant APR_CHANGE_COOLDOWN = 7 days;
    uint256 public constant MIN_AUTO_COMPOUND_AMOUNT = 0.01 ether;

    // Stake periods configuration
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

    // Events
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

        _initializeStakePeriods();
    }

    /**
     * @notice Initialize default stake periods
     */
    function _initializeStakePeriods() internal {
        stakePeriods.push(StakePeriodConfig(28, true, 0)); // 4 weeks
        stakePeriods.push(StakePeriodConfig(56, true, 0)); // 8 weeks
        stakePeriods.push(StakePeriodConfig(84, true, 0)); // 12 weeks
        stakePeriods.push(StakePeriodConfig(168, true, 0)); // 24 weeks
        stakePeriods.push(StakePeriodConfig(365, true, 0)); // 52 weeks
    }

    // -- User Functions --

    /**
     * @notice Stake tokens for a specific period
     * @param amount Amount of tokens to stake
     * @param periodIndex Index of the stake period (0-4)
     * @param autoCompound Whether to auto-compound rewards
     */
    function stake(uint256 amount, uint8 periodIndex, bool autoCompound) external nonReentrant {
        require(amount > 0, "Cannot stake 0 tokens");
        require(periodIndex < stakePeriods.length, "Invalid period index");
        require(stakePeriods[periodIndex].active, "Stake period not active");
        require(rewardPool.fundsAvailable, "No active rewardPool");

        StakePeriodConfig storage period = stakePeriods[periodIndex];

        uint256 reservedReward = (amount * period.scaledAPR * period.durationInDays) / (BPS_DIVISOR * 365);

        require(
            rewardPool.totalFunded >= rewardPool.totalReserved + reservedReward,
            "Insufficient reward pool for this stake"
        );

        governanceToken.transferFrom(msg.sender, address(this), amount);

        uint256 unlockTime = block.timestamp + (period.durationInDays * 1 days);

        UserStake memory newStake = UserStake({
            amount: amount,
            stakedAt: block.timestamp,
            unlockTime: unlockTime,
            stakePeriodDays: period.durationInDays,
            aprInBps: period.scaledAPR,
            lastClaimTime: block.timestamp,
            reservedReward: reservedReward,
            autoCompound: autoCompound,
            active: true,
            withdrawn: false,
            periodIndex: periodIndex
        });

        userStakes[msg.sender].push(newStake);
        uint256 stakeIndex = userStakes[msg.sender].length - 1;

        totalStaked += amount;
        rewardPool.totalReserved += reservedReward;

        emit Staked(msg.sender, amount, period.scaledAPR, stakeIndex, unlockTime, periodIndex, autoCompound);
    }

    /**
     * @notice Claim rewards from a specific stake (available during stake period)
     * @param stakeIndex Index of the stake to claim from
     */
    function claimRewards(uint256 stakeIndex) public nonReentrant {
        require(stakeIndex < userStakes[msg.sender].length, "Invalid stake index");

        UserStake storage userStake = userStakes[msg.sender][stakeIndex];
        require(userStake.active && !userStake.withdrawn, "Invalid stake");

        uint256 rewards = _calculateAccruedReward(msg.sender, stakeIndex);
        require(rewards > 0, "No rewards to claim");

        userStake.lastClaimTime = block.timestamp;

        if (userStake.autoCompound && rewards >= MIN_AUTO_COMPOUND_AMOUNT && rewardPool.fundsAvailable) {
            _createAutoCompoundStake(msg.sender, rewards);
            emit RewardsClaimed(msg.sender, rewards, stakeIndex, true);
        } else {
            governanceToken.transfer(msg.sender, rewards);
            emit RewardsClaimed(msg.sender, rewards, stakeIndex, false);
        }
    }

    /**
     * @notice Withdrawn principal + remaining rewards after stake period completion
     * @param stakeIndex Index of the stake to withdraw
     */
    function withdraw(uint256 stakeIndex) external nonReentrant {
        require(stakeIndex < userStakes[msg.sender].length, "Invalid stake index");

        UserStake storage userStake = userStakes[msg.sender][stakeIndex];
        require(userStake.active && !userStake.withdrawn, "Invalid Stake");
        require(block.timestamp >= userStake.unlockTime, "Stake period not completed");

        uint256 finalRewards = _calculateAccruedReward(msg.sender, stakeIndex);

        userStake.withdrawn = true;
        userStake.active = false;

        totalStaked -= userStake.amount;
        rewardPool.totalReserved -= userStake.reservedReward;

        uint256 totalWithdraw = userStake.amount;
        if (finalRewards > 0) {
            if (userStake.autoCompound && finalRewards >= MIN_AUTO_COMPOUND_AMOUNT && rewardPool.fundsAvailable) {
                _createAutoCompoundStake(msg.sender, finalRewards);
            } else {
                totalWithdraw += finalRewards;
            }
        }

        governanceToken.transfer(msg.sender, totalWithdraw);
        emit Withdrawn(msg.sender, userStake.amount, stakeIndex, finalRewards);
    }

    /**
     * @notice Restake principal + rewards into a new stake period
     * @param stakeIndex Index of the completed stake
     * @param newPeriodIndex New stake period index
     */
    function restake(uint256 stakeIndex, uint8 newPeriodIndex) external nonReentrant {
        require(stakeIndex < userStakes[msg.sender].length, "Invalid stake index");
        require(newPeriodIndex < stakePeriods.length, "Invalid Period index");
        require(stakePeriods[newPeriodIndex].active, "New period not active");

        UserStake storage oldStake = userStakes[msg.sender][stakeIndex];
        require(oldStake.active && !oldStake.withdrawn, "Invalid stake");
        require(block.timestamp >= oldStake.unlockTime, "Stake period not completed");

        uint256 finalRewards = _calculateAccruedReward(msg.sender, stakeIndex);
        uint256 restakeAmount = oldStake.amount + finalRewards;

        oldStake.withdrawn = true;
        oldStake.active = false;
        totalStaked -= oldStake.amount;
        rewardPool.totalReserved -= oldStake.reservedReward;

        StakePeriodConfig storage newPeriod = stakePeriods[newPeriodIndex];
        uint256 newReservedReward =
            (restakeAmount * newPeriod.scaledAPR * newPeriod.durationInDays) / (BPS_DIVISOR * 365);

        require(
            rewardPool.totalFunded >= rewardPool.totalReserved + newReservedReward,
            "Insufficient reward pool for restake"
        );

        uint256 newUnlockTime = block.timestamp + (newPeriod.durationInDays * 1 days);

        UserStake memory newStake = UserStake({
            amount: restakeAmount,
            stakedAt: block.timestamp,
            unlockTime: newUnlockTime,
            stakePeriodDays: newPeriod.durationInDays,
            aprInBps: newPeriod.scaledAPR,
            lasstClaimTime: block.timestamp,
            reservedReward: newReservedReward,
            autoCompound: oldStake.autoCompound,
            active: true,
            withdraw: false,
            periodIndex: newPeriodIndex
        });

        userStakes[msg.sender].push(newStake);
        uint256 newStakeIndex = userStakes[msg.sender].length - 1;

        totalStaked += restakeAmount;
        rewardPool.totalReserved += newReservedReward;

        emit Restaked(msg.sender, stakeIndex, newStakeIndex, newPeriodIndex);
    }

    /**
     * @notice Claim rewards from all active stakes
     */
    function claimAllRewards() external {
        uint256 stakeCount = userStakes[msg.sender].length;
        require(stakeCount > 0, "No stakes found");

        for (uint256 i = 0; i < stakeCount; i++) {
            UserStake storage userStake = userStakes[msg.sender][i];
            if (userStake.active && !userStake.withdrawn) {
                uint256 rewards = _calculateAccruedReward(msg.sender, i);
                if (rewards > 0) {
                    claimRewards(i);
                }
            }
        }
    }

    /**
     * @notice Toggle auto-compound for a specific stake
     */
    function setAutoCompound(uint256 stakeIndex, bool enabled) external {
        require(stakeIndex < userStakes[msg.sender].length, "Invalid stake index");
        UserStake storage userStake = userStakes[msg.sender][stakeIndex];
        require(userStake.active && !userStake.withdrawn, "Invalid stake");

        userStake.autoCompound = enabled;
        emit AutoCompoundToggled(msg.sender, stakeIndex, enabled);
    }

    // -- Owner Functions --

    /**
     * @notice Set base APR for 365 days (other periods auto-scale)
     * @param baseAPRFor365Days APR in basis points for 365-day stakes
     */
    function setBaseAPR(uint256 baseAPRFor365Days) external onlyOwner {
        require(baseAPRFor365Days > 0 && baseAPRFor365Days <= MAX_APR, "Invalid base APR");
        require(block.timestamp >= rewardPool.lastAPRChange + APR_CHANGE_COOLDOWN, "APR change cooldown not completed");

        rewardPool.baseAPRFor365Days = baseAPRFor365Days;
        rewardPool.lastAPRChange = block.timestamp;

        for (uint256 i = 0; i < stakePeriods.length; i++) {
            stakePeriods[i].scaledAPR = (baseAPRFor365Days * stakePeriods[i].durationInDays) / 365;
        }

        emit BaseAPRUpdated(baseAPRFor365Days);
    }

    /**
     * @notice Fund the reward pool
     * @param amount Amount of tokens to add to reward pool
     */
    function fundRewardPool(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be greater than 0");

        uint256 balanceBefore = governanceToken.balanceOf(address(this));
        governanceToken.transferFrom(msg.sender, address(this), amount);
        uint256 balanceAfter = governanceToken.balanceOf(address(this));
        require(balanceAfter >= balanceBefore + amount, "Token transfer failed");

        rewardPool.totalFunded += amount;
        rewardPool.fundsAvailable = true;

        emit RewardPoolFunded(amount);
    }

    /**
     * @notice Toggle stake period availability
     */
    function toggleStakePeriod(uint8 periodIndex, bool active) external onlyOwner {
        require(periodIndex < stakePeriods.length, "Invalid period index");

        stakePeriods[periodIndex].active = active;
        emit StakePeriodToggled(periodIndex, active);
    }

    /**
     * @notice Withdraw excess funds reserved for stakes
     */
    function withdrawExcessFunds(uint256 amount) external onlyOwner {
        uint256 contractBalance = governanceToken.balanceOf(address(this));
        uint256 availableBalance = contractBalance - totalStaked - rewardPool.totalReserved;

        require(amount <= availableBalance, "Insufficient excess funds");
        require(amount > 0, "Amount must be greater than 0");

        if (amount == rewardPool.totalFunded - rewardPool.totalReserved) {
            rewardPool.fundsAvailable = false;
        }

        rewardPool.totalFunded -= amount;
        governanceToken.transfer(msg.sender, amount);

        emit ExcessFundsWithdrawn(amount);
    }

    // -- Internal Functions --
    function _calculateAccuredReward(address user, uint256 stakeIndex) internal view returns (uint256) {}
}
