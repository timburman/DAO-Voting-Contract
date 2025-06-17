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

