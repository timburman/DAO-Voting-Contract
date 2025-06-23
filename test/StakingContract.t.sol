// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/StakingContract.sol";
import "../src/GovernanceToken.sol";

contract TestStakingContract is Test {
    StakingContract public stakingContract;
    GovernanceToken public token;
    address public owner;

    function setUp() public {
        owner = makeAddr("owner");
        vm.startPrank(owner);
        token = new GovernanceToken("Token", "TKN", 100000, owner);
        stakingContract = new StakingContract(address(token), owner);
        vm.stopPrank();
    }

    function testTokenName() public view {
        assertEq(token.name(), "Token");
    }
}
