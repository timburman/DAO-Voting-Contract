# Solidity API

## IStakingContract

### Contract
IStakingContract : contracts/IStakingContract.sol

 --- 
### Functions:
### getVotingPower

```solidity
function getVotingPower(address _account) external view returns (uint256)
```

Gets the staked balance of an account (voting power).

_In a basic system, this is the current balance._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _account | address | The address to query. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The amount of tokens staked by the account. |

### totalStaked

```solidity
function totalStaked() external view returns (uint256)
```

Gets the total amount of tokens staked in the contract.

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The total staked amount. |

## VotingContract

_Manages DAO Proposals and votes_

### Contract
VotingContract : contracts/VotingContract.sol

Manages DAO Proposals and votes

 --- 
### Functions:
### constructor

```solidity
constructor(address _stakingContractAddress, uint256 _initialQuorumBasisPoints, address _initialOwner) public
```

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _stakingContractAddress | address | Address of the deployed StakingContract. |
| _initialQuorumBasisPoints | uint256 | Quorum requirement |
| _initialOwner | address | Owner of this contract. |

### createProposal

```solidity
function createProposal(string _description) external returns (uint256)
```

Creates a new proposal.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _description | string | Text describing the proposal. |

### cancelProposal

```solidity
function cancelProposal(uint256 _proposalId) external
```

Allows the proposer to cancel an active proposal.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | The ID of the proposal to cancel. |

### casteVote

```solidity
function casteVote(uint256 _proposalId, enum VotingContract.VoteType _voteType) external
```

Allows the users to caste the vote on an active proposal

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | the proposal Id |
| _voteType | enum VotingContract.VoteType | vote for, against or abstrain |

### finishProposal

```solidity
function finishProposal(uint256 _proposalId) external
```

Allows everyone to finish the proposal after its voting period is over

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | the proposal id |

### getProposal

```solidity
function getProposal(uint256 _proposalId) external view returns (uint256 id, address proposer, string description, uint256 startTime, uint256 endTime, uint256 forVotes, uint256 againstVotes, uint256 abstainVotes, uint256 totalVotesParticipated, uint256 snapshotTotalStaked, bool canceled, enum VotingContract.ProposalState state)
```

Fetches the proposal using proposalId

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | proposal id to fetch |

### getVote

```solidity
function getVote(uint256 _proposalId, address _voter) external view returns (bool hasVoted, enum VotingContract.VoteType voteChoice)
```

@notice

### setVotingPeriod

```solidity
function setVotingPeriod(uint256 _newVotingPeriod) external
```

### setQuorum

```solidity
function setQuorum(uint256 _newQuorumBasisPoints) external
```

inherits Ownable:
### owner

```solidity
function owner() public view virtual returns (address)
```

_Returns the address of the current owner._

### _checkOwner

```solidity
function _checkOwner() internal view virtual
```

_Throws if the sender is not the owner._

### renounceOwnership

```solidity
function renounceOwnership() public virtual
```

_Leaves the contract without owner. It will not be possible to call
`onlyOwner` functions. Can only be called by the current owner.

NOTE: Renouncing ownership will leave the contract without an owner,
thereby disabling any functionality that is only available to the owner._

### transferOwnership

```solidity
function transferOwnership(address newOwner) public virtual
```

_Transfers ownership of the contract to a new account (`newOwner`).
Can only be called by the current owner._

### _transferOwnership

```solidity
function _transferOwnership(address newOwner) internal virtual
```

_Transfers ownership of the contract to a new account (`newOwner`).
Internal function without access restriction._

 --- 
### Events:
### ProposalCreated

```solidity
event ProposalCreated(uint256 proposalId, address proposer, string description, uint256 startTime, uint256 endTime, uint256 snapShotTotalStaked)
```

### Voted

```solidity
event Voted(uint256 proposalId, address voter, enum VotingContract.VoteType voteType, uint256 votingPower)
```

### ProposalFinished

```solidity
event ProposalFinished(uint256 proposalId, enum VotingContract.ProposalState finalState, uint256 forVotes, uint256 againstVotes, uint256 abstainVotes)
```

### ProposalCanceled

```solidity
event ProposalCanceled(uint256 proposalId)
```

inherits Ownable:
### OwnershipTransferred

```solidity
event OwnershipTransferred(address previousOwner, address newOwner)
```

