// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract BasicVestingGovernanceToken is ERC20, ERC20Burnable, Ownable {
    uint256 public immutable vestingStartTime;
    uint256 public immutable vestingDuration;

    uint256 public immutable totalVestedSupply;

    uint256 public totalVestedReleased;

    event VestingScheduleCreated(
        uint256 totalAmount,
        uint256 startTime,
        uint256 duration
    );
    event VestedTokensReleased(address indexed to, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialOwnerSupply,
        uint256 _totalVestedSupply,
        uint256 _vestingDurationInSeconds,
        address _initialOwner
    ) ERC20(_name, _symbol) Ownable(_initialOwner) {
        require(
            _initialOwner != address(0),
            "Ownable: initial owner is the zero address"
        );
        require(
            _vestingDurationInSeconds > 0,
            "Vesting: duration must be greater than zero"
        );

        vestingStartTime = block.timestamp;
        vestingDuration = _vestingDurationInSeconds;
        totalVestedSupply = _totalVestedSupply;

        if (_initialOwnerSupply > 0) {
            _mint(_initialOwner, _initialOwnerSupply);
        }

        if (_totalVestedSupply > 0) {
            _mint(address(this), _totalVestedSupply);
        }

        emit VestingScheduleCreated(
            _totalVestedSupply,
            vestingStartTime,
            vestingDuration
        );
    }

    function currentlyVested() public view returns (uint256) {
        if (block.timestamp < vestingStartTime || vestingDuration == 0) {
            return 0;
        }

        uint timeElapsed = block.timestamp - vestingStartTime;

        if (timeElapsed >= vestingDuration) {
            return totalVestedSupply;
        }

        return (totalVestedSupply * timeElapsed) / vestingDuration;
    }

    function releaseVestedTokens() public onlyOwner {
        uint256 totalVestedAmount = currentlyVested();

        require(
            totalVestedAmount > totalVestedReleased,
            "Vesting: no new tokens have vested"
        );

        uint256 amountToRelease = totalVestedAmount - totalVestedReleased;

        totalVestedReleased = totalVestedReleased + amountToRelease;

        _transfer(address(this), owner(), amountToRelease);

        emit VestedTokensReleased(owner(), amountToRelease);
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._update(from, to, amount);

        if (from == address(this)) {
            require(
                to == owner() && msg.sender == owner(),
                "ERC20: cannot transfer locked vested tokens"
            );
        }
    }
}
