# Solidity API

## StakingContract

### Contract
StakingContract : contracts/StakingContract.sol

 --- 
### Functions:
### constructor

```solidity
constructor(address _tokenAddress, address _initialOwner) public
```

_Constructor sets the address of the Governance Token_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _tokenAddress | address | The address to deploy GovernanceToken contract |
| _initialOwner | address | The address that will own the contract |

### stake

```solidity
function stake(uint256 _amount) external
```

Stakes a specified amount of GovernanceToken.

_User must first approve this contract to spend their tokens._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _amount | uint256 | The amount of tokens to stake. |

### initiateUnstaking

```solidity
function initiateUnstaking(uint256 _amount) external
```

Initiates the unstaking process for a specified amount.

_Tokens remain locked for UNSTAKE_PERIOD. Only one unstake request active at a time per user._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _amount | uint256 | The amount of tokens to start unstaking. |

### withdraw

```solidity
function withdraw() external
```

Withdraws tokens after the unstaking period has passed.

_Can only be called after initiateUnstake and waiting UNSTAKE_PERIOD._

### getVotingPower

```solidity
function getVotingPower(address _account) external view returns (uint256)
```

Gets the staked balance of an account, which represents voting power.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _account | address | The address to query. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The amount of tokens staked by the account. |

### getUnstakedRequest

```solidity
function getUnstakedRequest(address _account) external view returns (uint256 amount, uint256 unlockTime)
```

Gets details of a pending unstake request for an account.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _account | address | The address to query. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | The amount pending withdrawal. |
| unlockTime | uint256 | The timestamp when withdrawal is possible. |

inherits ReentrancyGuard:
### _reentrancyGuardEntered

```solidity
function _reentrancyGuardEntered() internal view returns (bool)
```

_Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
`nonReentrant` function in the call stack._

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
### Staked

```solidity
event Staked(address user, uint256 amount)
```

### UnstakeInitiated

```solidity
event UnstakeInitiated(address user, uint256 amount, uint256 unlockTime)
```

### Withdraw

```solidity
event Withdraw(address user, uint256 amount)
```

inherits ReentrancyGuard:
inherits Ownable:
### OwnershipTransferred

```solidity
event OwnershipTransferred(address previousOwner, address newOwner)
```

