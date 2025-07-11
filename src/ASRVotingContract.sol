// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "./ASRStakingContract.sol";

/**
 * @title ASRVotingContract
 * @dev Adanced voting system with snapshots, multi-choice proposals, categories, and ASR integration.
 * @notice Integrates with ASRStakingContract for voting power and activity tracking.
 */
contract ASRVotingContract is Initializable, ReentrancyGuardUpgradeable, IERC165 {
    // -- Interface Support --
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
