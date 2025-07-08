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
    uint public cooldownPeriod;
    uint public minimumStakeAmount;
    uint public minimumUnstakeAmount;
    bool public emergencyMode;

    uint public constant MAX_UNSTAKE_REQUESTS = 3;
    uint public constant MIN_COOLDOWN = 7 days;
    uint public constant MAX_COOLDOWN = 30 days;

    mapping(address => uint) private _balances;
    uint public totalStaked;

    // Unstake Requests
    struct UnstakeRequest {
        uint amount;
        uint requestTime;
        bool claimed;
    }
    mapping(address => UnstakeRequest[]) public unstakeRequests;

    // -- Events --
    event staked(
        address indexed user,
        uint amount,
        uint newTotalStaked,
        uint newUserBalance
    );

    event UnstakeRequested(
        address indexed user,
        uint amount,
        uint requestTime,
        uint requestIndex,
        uint claimableAt
    );

    event UnstakeClaimed(
        address indexed user,
        uint amount,
        uint requestIndex
    );

    event BatchUnstakeClaimed(
        address indexed user,
        uint totalAmount,
        uint requestCount
    );

    event CooldownPeriodUpdated(uint newCooldown);
    event MinimumAmountUpdated(uint minStake, uint minUnstake);
    event EmergencyModeUpdated(bool enabled);
    event OwnershipTransferred(address indexed previosOwner, address indexed newOwner);

    // -- Mofifier --
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // -- Initialization --
    function initialize(
        address _stakingToken,
        uint _cooldownPeriod,
        address _owner
    ) public initializer {
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
    
}
