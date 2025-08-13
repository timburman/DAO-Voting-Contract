// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract ReactiveStaking is ReentrancyGuardUpgradeable {

    // -- State Variables --

    /// @notice The ERC20 token for staking
    IERC20 internal stakingToken;
    /// @notice The address of VotingContract, only authorized contract to manage proposals
    address internal votingContract;

    // -- Staking Balances --
    mapping(address => uint) private _balances;
    uint private _totalStaked;

    // -- Config --
    uint internal _cooldownPeriod;
    uint internal _minimumStakeAmount;
    uint internal _minimumUnstakeAmount;
    bool internal _emergencyMode;

    // -- Constants --
    uint public constant MAX_UNSTAKE_REQUESTS = 3;
    uint public constant MIN_COOLDOWN = 7 days;
    uint public constant MAX_COOLDOWN = 30 days;

    // -- Proposal State --
    bool internal _isProposalActive;
    uint internal _currentProposalPeriod;
    uint internal _activeProposalCount;
    uint internal _totalProposalCount;
    uint public constant MAX_ACTIVE_PROPOSAL = 3;

    // -- Structs --
    





}