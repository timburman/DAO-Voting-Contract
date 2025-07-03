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

    struct StakeInfo {
        uint256 amount;
        uint256 stakedAt;
        uint256 unlockTime;
        uint256 stakePeriodDays;
        uint256 aprInBps;
        uint256 pendingRewards;
        bool autoCompound;
        bool active;
        bool canWithdraw;
        uint8 periodIndex;
    }

    struct CompoundPool {
        uint256 totalAmount;
        uint256 lastUpdateTime;
        uint8 preferredPeriodIndex;
        bool hasActivePool;
    }

    // Reward pool management
    StakePeriodConfig[] public stakePeriods;
    mapping(address => UserStake[]) public userStakes;
    RewardPool public rewardPool;
    uint256 public totalStaked;
    mapping(address => CompoundPool) public userCompoundPools;

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
    event RewardsAddedToPool(address indexed user, uint256 amount, uint256 totalPoolAmount);
    event CompoundPoolFlushed(address indexed user, uint256 amount, uint256 newStakeIndex, uint8 periodIndex);
    event Restaked(address indexed user, uint256 stakeIndex, uint256 newStakeIndex, uint8 newPeriodIndex);
    event BaseAPRUpdated(uint256 newBaseAPR);
    event StakePeriodToggled(uint8 periodIndex, bool active);
    event AutoCompoundToggled(address indexed user, uint256 stakeIndex, bool enabled);
    event RewardPoolFunded(uint256 amount);
    event ExcessFundsWithdrawn(uint256 amount);

    constructor(address _governanceToken, uint256 _baseAPRFor365Days) Ownable(msg.sender) {
        governanceToken = IERC20(_governanceToken);

        _initializeStakePeriods();

        _setBaseAPRInternal(_baseAPRFor365Days);
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
            _addToCompoundPool(msg.sender, rewards, userStake.periodIndex);
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
            lastClaimTime: block.timestamp,
            reservedReward: newReservedReward,
            autoCompound: oldStake.autoCompound,
            active: true,
            withdrawn: false,
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

    /**
     * @notice Manually flush compound pool into new stake
     * @param periodIndex Period index for the new stake
     */
    function flushCompoundPool(uint8 periodIndex) external nonReentrant {
        require(periodIndex < stakePeriods.length, "Invalid period index");
        require(stakePeriods[periodIndex].active, "Period not active");

        CompoundPool storage pool = userCompoundPools[msg.sender];
        require(pool.hasActivePool && pool.totalAmount > 0, "No compound pool to flush");

        _flushCompoundPoolInternal(msg.sender, periodIndex);
    }

    /**
     * @notice Flush compound pool using preferred period
     */
    function flushCompoundPoolAuto() external nonReentrant {
        CompoundPool storage pool = userCompoundPools[msg.sender];
        require(pool.hasActivePool && pool.totalAmount > 0, "No compound pool to flush");
        require(stakePeriods[pool.preferredPeriodIndex].active, "Preferred period not active");

        _flushCompoundPoolInternal(msg.sender, pool.preferredPeriodIndex);
    }

    /**
     * @notice Withdraw all rewards from compound pool (disable auto-compound)
     */
    function withdrawFromCompoundPool() external nonReentrant {
        CompoundPool storage pool = userCompoundPools[msg.sender];
        require(pool.hasActivePool && pool.totalAmount > 0, "No active compound pool");

        uint256 poolAmount = pool.totalAmount;

        pool.totalAmount = 0;
        pool.hasActivePool = false;

        governanceToken.transfer(msg.sender, poolAmount);

        emit RewardsAddedToPool(msg.sender, 0, 0);
    }

    // -- Owner Functions --

    /**
     * @notice Set base APR for 365 days (other periods auto-scale)
     * @param baseAPRFor365Days APR in basis points for 365-day stakes
     */
    function setBaseAPR(uint256 baseAPRFor365Days) external onlyOwner {
        require(baseAPRFor365Days > 0 && baseAPRFor365Days <= MAX_APR, "Invalid base APR");

        require(block.timestamp >= rewardPool.lastAPRChange + APR_CHANGE_COOLDOWN, "APR change cooldown not completed");
        require(baseAPRFor365Days != rewardPool.baseAPRFor365Days, "APR already set to this value");

        _setBaseAPRInternal(baseAPRFor365Days);

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
    function _calculateAccruedReward(address user, uint256 stakeIndex) internal view returns (uint256) {
        UserStake storage userStake = userStakes[user][stakeIndex];
        if (!userStake.active || userStake.withdrawn) return 0;

        uint256 stakingDuration = block.timestamp - userStake.lastClaimTime;
        uint256 maxDuration =
            userStake.unlockTime > userStake.lastClaimTime ? userStake.unlockTime - userStake.lastClaimTime : 0;
        uint256 rewardDuration = stakingDuration < maxDuration ? stakingDuration : maxDuration;

        if (rewardDuration == 0) return 0;

        return (userStake.amount * userStake.aprInBps * rewardDuration) / (BPS_DIVISOR * 365 days);
    }

    /**
     * @notice Create auto-compound stake with best available period
     */
    function _createAutoCompoundStake(address user, uint256 rewardAmount) internal {
        uint8 bestPeriodIndex = 0;
        bool foundPeriod = false;

        for (uint8 i = uint8(stakePeriods.length); i > 0; i--) {
            uint8 index = i - 1;
            if (stakePeriods[index].active) {
                // Check if reward pool can sustain this auto-compound
                uint256 newReservedReward = (
                    rewardAmount * stakePeriods[index].scaledAPR * stakePeriods[index].durationInDays
                ) / (BPS_DIVISOR * 365);

                if (rewardPool.totalFunded >= rewardPool.totalReserved + newReservedReward) {
                    bestPeriodIndex = index;
                    foundPeriod = true;
                    break;
                }
            }
        }

        if (!foundPeriod) {
            governanceToken.transfer(user, rewardAmount);
            return;
        }

        StakePeriodConfig storage period = stakePeriods[bestPeriodIndex];
        uint256 reservedReward = (rewardAmount * period.scaledAPR * period.durationInDays) / (BPS_DIVISOR * 365);
        uint256 unlockTime = block.timestamp + (period.durationInDays * 1 days);

        UserStake memory compoundStake = UserStake({
            amount: rewardAmount,
            stakedAt: block.timestamp,
            unlockTime: unlockTime,
            stakePeriodDays: period.durationInDays,
            aprInBps: period.scaledAPR,
            lastClaimTime: block.timestamp,
            reservedReward: reservedReward,
            autoCompound: true,
            active: true,
            withdrawn: false,
            periodIndex: bestPeriodIndex
        });

        userStakes[user].push(compoundStake);
        totalStaked += rewardAmount;
        rewardPool.totalReserved += reservedReward;
    }

    function _setBaseAPRInternal(uint256 baseAPRFor365Days) internal {
        rewardPool.baseAPRFor365Days = baseAPRFor365Days;
        rewardPool.lastAPRChange = block.timestamp;

        for (uint256 i = 0; i < stakePeriods.length; i++) {
            stakePeriods[i].scaledAPR = (baseAPRFor365Days * stakePeriods[i].durationInDays) / 365;
        }
    }

    /**
     * @notice Add rewards to user's compound pool
     * @param user User address
     * @param amount Reward amount to add
     * @param preferredPeriod Preferred period for future flush
     */
    function _addToCompoundPool(address user, uint256 amount, uint8 preferredPeriod) internal {
        CompoundPool storage pool = userCompoundPools[user];

        pool.totalAmount += amount;
        pool.lastUpdateTime = block.timestamp;
        pool.hasActivePool = true;

        if (pool.preferredPeriodIndex < preferredPeriod) {
            pool.preferredPeriodIndex = preferredPeriod;
        }

        emit RewardsAddedToPool(user, amount, pool.totalAmount);

        _autoFlushIfNeeded(user);
    }

    /**
     * @notice Auto-flush compound pool when it reaches threshold
     * @param user User address
     */
    function _autoFlushIfNeeded(address user) internal {
        CompoundPool storage pool = userCompoundPools[user];
        if (pool.totalAmount >= 100 ether && pool.hasActivePool) {
            _flushCompoundPoolInternal(user, pool.preferredPeriodIndex);
        }
    }

    /**
     * @notice Internal function to flush compound pool
     * @param user User address
     * @param periodIndex Period index for new stake
     */
    function _flushCompoundPoolInternal(address user, uint8 periodIndex) internal {
        CompoundPool storage pool = userCompoundPools[user];
        require(pool.hasActivePool && pool.totalAmount > 0, "No active compound pool");

        uint256 poolAmount = pool.totalAmount;

        StakePeriodConfig storage period = stakePeriods[periodIndex];
        uint256 reservedReward = (poolAmount * period.scaledAPR * period.durationInDays) / (BPS_DIVISOR * 365);

        require(
            rewardPool.totalFunded >= rewardPool.totalReserved + reservedReward,
            "Insufficient reward pool for compound flush"
        );

        uint256 unlockTime = block.timestamp + (period.durationInDays * 1 days);

        UserStake memory newStake = UserStake({
            amount: poolAmount,
            stakedAt: block.timestamp,
            unlockTime: unlockTime,
            stakePeriodDays: period.durationInDays,
            aprInBps: period.scaledAPR,
            lastClaimTime: block.timestamp,
            reservedReward: reservedReward,
            autoCompound: true,
            active: true,
            withdrawn: false,
            periodIndex: periodIndex
        });

        userStakes[user].push(newStake);
        uint256 newStakeIndex = userStakes[user].length - 1;

        totalStaked += poolAmount;
        rewardPool.totalReserved += reservedReward;

        pool.totalAmount = 0;
        pool.hasActivePool = false;

        emit CompoundPoolFlushed(user, poolAmount, newStakeIndex, periodIndex);
    }
    // -- View functions --

    /**
     * @notice Get number of stake periods available
     */
    function getStakePeriodsCount() external view returns (uint256) {
        return stakePeriods.length;
    }

    /**
     * @notice get stake period configuration
     */
    function getStakePeriod(uint8 periodIndex)
        external
        view
        returns (uint256 durationInDays, bool active, uint256 scaledAPR)
    {
        require(periodIndex < stakePeriods.length, "Invalid period index");
        StakePeriodConfig storage period = stakePeriods[periodIndex];
        return (period.durationInDays, period.active, period.scaledAPR);
    }

    /**
     * @notice Get all active stake periods
     */
    function getActiveStakePeriods()
        external
        view
        returns (uint8[] memory indices, uint256[] memory durations, uint256[] memory aprs)
    {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < stakePeriods.length; i++) {
            if (stakePeriods[i].active) activeCount++;
        }

        indices = new uint8[](activeCount);
        durations = new uint256[](activeCount);
        aprs = new uint256[](activeCount);

        uint256 currentIndex = 0;
        for (uint8 i = 0; i < stakePeriods.length; i++) {
            if (stakePeriods[i].active) {
                indices[currentIndex] = i;
                durations[currentIndex] = stakePeriods[i].durationInDays;
                aprs[currentIndex] = stakePeriods[i].scaledAPR;
                currentIndex++;
            }
        }
    }

    /**
     * @notice Get user's stake count
     */
    function getStakeCount(address user) external view returns (uint256) {
        return userStakes[user].length;
    }

    /**
     * @notice Get user's stake count
     */
    function getTotalStaked(address user) public view returns (uint256) {
        uint256 total = 0;
        UserStake[] storage stakes = userStakes[user];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (stakes[i].active && !stakes[i].withdrawn) {
                total += stakes[i].amount;
            }
        }
        return total;
    }

    /**
     * @notice Get expected reward for a specific stake
     */
    function getExpectedReward(address user, uint256 stakeIndex) external view returns (uint256) {
        require(stakeIndex < userStakes[user].length, "Invalid stake index");
        return _calculateAccruedReward(user, stakeIndex);
    }

    /**
     * @notice Get total exprected rewards for all active stakes
     */
    function getTotalExpectedRewards(address user) public view returns (uint256) {
        uint256 total = 0;
        UserStake[] storage stakes = userStakes[user];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (stakes[i].active && !stakes[i].withdrawn) {
                total += _calculateAccruedReward(user, i);
            }
        }
        return total;
    }

    /**
     * @notice Estimate reward for amount and period
     */
    function estimateRewardForPeriod(uint256 amount, uint8 periodIndex) external view returns (uint256) {
        require(periodIndex < stakePeriods.length, "Invalid period index");

        StakePeriodConfig storage period = stakePeriods[periodIndex];
        return (amount * period.scaledAPR * period.durationInDays) / (BPS_DIVISOR * 365);
    }

    /**
     * @notice Get reward pool status
     */
    function getRewardPoolStatus()
        external
        view
        returns (
            uint256 totalFunded,
            uint256 totalReserved,
            uint256 availableFunding,
            uint256 baseAPR,
            bool fundsAvailable
        )
    {
        uint256 available =
            rewardPool.totalFunded > rewardPool.totalReserved ? rewardPool.totalFunded - rewardPool.totalReserved : 0;

        return (
            rewardPool.totalFunded,
            rewardPool.totalReserved,
            available,
            rewardPool.baseAPRFor365Days,
            rewardPool.fundsAvailable
        );
    }

    /**
     * @notice get detailed stake information
     */
    function getStakeInfo(address user, uint256 stakeIndex) external view returns (StakeInfo memory) {
        require(stakeIndex < userStakes[user].length, "Invalid stake index");

        UserStake storage userStake = userStakes[user][stakeIndex];
        return StakeInfo({
            amount: userStake.amount,
            stakedAt: userStake.stakedAt,
            unlockTime: userStake.unlockTime,
            stakePeriodDays: userStake.stakePeriodDays,
            aprInBps: userStake.aprInBps,
            pendingRewards: _calculateAccruedReward(user, stakeIndex),
            autoCompound: userStake.autoCompound,
            active: userStake.active && !userStake.withdrawn,
            canWithdraw: block.timestamp >= userStake.unlockTime && userStake.active && !userStake.withdrawn,
            periodIndex: userStake.periodIndex
        });
    }

    /**
     * @notice Check if APR can be changed
     */
    function canChangeAPR() external view returns (bool) {
        return block.timestamp >= rewardPool.lastAPRChange + APR_CHANGE_COOLDOWN;
    }

    /**
     * @notice Get time until next APR change allowed
     */
    function timeUntilNextAPRChange() external view returns (uint256) {
        uint256 nextChangeTime = rewardPool.lastAPRChange + APR_CHANGE_COOLDOWN;
        return block.timestamp >= nextChangeTime ? 0 : nextChangeTime - block.timestamp;
    }

    /**
     * @notice Get all user stakes with details
     */
    function getAllUserStakes(address user)
        external
        view
        returns (
            uint256[] memory amounts,
            uint256[] memory unlockTimes,
            uint256[] memory aprs,
            bool[] memory canWithdrawList,
            uint8[] memory periodIndices
        )
    {
        uint256 stakeCount = userStakes[user].length;

        amounts = new uint256[](stakeCount);
        unlockTimes = new uint256[](stakeCount);
        aprs = new uint256[](stakeCount);
        canWithdrawList = new bool[](stakeCount);
        periodIndices = new uint8[](stakeCount);

        for (uint256 i = 0; i < stakeCount; i++) {
            UserStake storage stake_ = userStakes[user][i];
            amounts[i] = stake_.amount;
            unlockTimes[i] = stake_.unlockTime;
            aprs[i] = stake_.aprInBps;
            canWithdrawList[i] = block.timestamp >= stake_.unlockTime && stake_.active && !stake_.withdrawn;
            periodIndices[i] = stake_.periodIndex;
        }
    }

    /**
     * @notice Get compound pool information for a user
     * @param user User address
     * @return totalAmount Total rewards accumulated in pool
     * @return lastUpdateTime Last time rewards were added
     * @return preferredPeriodIndex Preferred period for flushing
     * @return hasActivePool Whether pool has any rewards
     */
    function getCompoundPoolInfo(address user)
        external
        view
        returns (uint256 totalAmount, uint256 lastUpdateTime, uint8 preferredPeriodIndex, bool hasActivePool)
    {
        CompoundPool storage pool = userCompoundPools[user];
        return (pool.totalAmount, pool.lastUpdateTime, pool.preferredPeriodIndex, pool.hasActivePool);
    }

    /**
     * @notice Get compound pool value for a user
     * @param user User address
     * @return Total amount in compound pool
     */
    function getCompoundPoolValue(address user) external view returns (uint256) {
        return userCompoundPools[user].totalAmount;
    }

    /**
     * @notice Check if user has an active compound pool
     * @param user User address
     * @return Whether user has rewards in compound pool
     */
    function hasCompoundPool(address user) external view returns (bool) {
        return userCompoundPools[user].hasActivePool && userCompoundPools[user].totalAmount > 0;
    }

    /**
     * @notice Get compound pool threshold for auto-flush
     * @return Threshold amount for auto-flush (100 ether)
     */
    function getCompoundPoolThreshold() external pure returns (uint256) {
        return 100 ether;
    }

    /**
     * @notice Get total user balance including staked + compound pool
     * @param user User address
     * @return Total balance across all stakes and compound pool
     */
    function getTotalUserBalance(address user) external view returns (uint256) {
        uint256 totalUserStaked = getTotalStaked(user);
        uint256 totalPending = getTotalExpectedRewards(user);
        uint256 compoundPool = userCompoundPools[user].totalAmount;

        return totalUserStaked + totalPending + compoundPool;
    }
}
