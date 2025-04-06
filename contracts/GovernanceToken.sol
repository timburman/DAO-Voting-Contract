// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GovernanceToken
 * @dev A simple ERC20 token for DAO governance.
 * Implements IERC20 via the ERC20 standard contract.
 * Owner can mint the initial supply.
 */
contract GovernanceToken is ERC20, Ownable {
    constructor(string memory _name, string memory _symbol, uint256 _initialSupply, address _initialOwner) ERC20(_name, _symbol) Ownable(_initialOwner) {
        require(_initialOwner != address(0));
        _mint(_initialOwner, _initialSupply);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
