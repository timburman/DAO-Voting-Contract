// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


contract AdvancedGovernanceToken is ERC20, ERC20Burnable, Ownable {

    using SafeMath for uint256;

    uint256 public immutable vestingStartTime;
    uint256 public immutable vestingDuration;

    uint256 public immutable totalVestedSupply;

    uint256 public totalVestedReleased;


    event VestingScheduleCreated(uint256 totalAmount, uint256 startTime, uint256 duration);
    event VestedTokensReleased(address indexed to, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialOwnerSupply,
        uint256 _totalVestedSupply,
        uint256 _vestingDurationInSeconds,
        address _initialOwner
    ) ERC20(_name, _symbol) Ownable(_initialOwner) {

        require(_initialOwner != address(0), "Ownable: initial owner is the zero address");
        require(_vestingDurationInSeconds > 0, "Vesting: duration must be greater than zero");

        vestingStartTime = block.timestamp;
        vestingDuration = _vestingDurationInSeconds;
        totalVestedSupply = _totalVestedSupply;

        if (_initialOwnerSupply > 0) {
            _mint(_initialOwner, _initialOwnerSupply);
        }

        if (_totalVestedSupply > 0) {
            _mint(address(this), _totalVestedSupply);
        }

        emit VestingScheduleCreated(_totalVestedSupply, vestingStartTime, vestingDuration);

    }


}