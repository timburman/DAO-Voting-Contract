// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title GovernanceToken
 * @dev A simple ERC20 token for DAO governance.
 * Implements IERC20 via the ERC20 standard contract.
 * Owner can mint the initial supply.
 */
contract GovernanceToken is ERC20, Ownable {
    /**
     * @dev Constructor sets the token name, symbol, and mints initial supply to the deployer.
     * @param _name The name of the token
     * @param _symbol The Symbol of the token
     * @param _initialSupply The inital supply of the token
     * @param _initialOwner The owner of the token that will recieve all the tokens
     */
    constructor(string memory _name, string memory _symbol, uint256 _initialSupply, address _initialOwner)
        ERC20(_name, _symbol)
        Ownable(_initialOwner)
    {
        require(_initialOwner != address(0));
        _mint(_initialOwner, _initialSupply);
    }

    /**
     * @dev Optional: Allows the owner to mint more tokens later if needed.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
