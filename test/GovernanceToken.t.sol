// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GovernanceToken.sol";

contract TestingGovernanceToken is Test {
    GovernanceToken public governanceToken;
    address owner;

    function setUp() public {
        owner = makeAddr("owner");
        vm.prank(owner);
        governanceToken = new GovernanceToken("Test", "TK", 1000000, owner);
    }

    function testName() public view {
        assertEq(governanceToken.name(), "Test");
    }

    function testOwner() public view {
        assertEq(governanceToken.owner(), owner);
    }

    function testOwnerCanMint() public {
        vm.startPrank(owner);
        uint256 startSupply = governanceToken.totalSupply();
        governanceToken.mint(owner, 1000);
        vm.stopPrank();
        assertEq(governanceToken.totalSupply(), startSupply + 1000);
    }

    function testOnlyOwnerCanMint(address _jane) public {
        vm.assume(_jane != owner);
        vm.prank(_jane);
        vm.expectRevert();
        governanceToken.mint(_jane, 1000);
    }
}
