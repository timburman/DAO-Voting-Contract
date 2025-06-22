// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakingContract {
    /**
     * @notice Gets the staked balance of an account (voting power).
     * @dev In a basic system, this is the current balance.
     * @param _account The address to query.
     * @return The amount of tokens staked by the account.
     */
    function getVotingPower(address _account) external view returns (uint256);

    /**
     * @notice Gets the total amount of tokens staked in the contract.
     * @return The total staked amount.
     */
    function totalStaked() external view returns (uint256);
}
