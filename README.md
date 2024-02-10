# StakinManager

**Contract to manage staking deposits, auto compounding of interest and mints token to represent deposits and rewards**

## Contracts
    - StakerManager.sol
    - Configuration: 
            - rewardsPerBlock
            - operator address
            - rewards token address
            - unstake period
            - rewards duration cycle in weeks
            
    - ERC20 reward token

## Actors
    - ADMIN_ROLE
    - OPERATOR_ROLE
    - STAKER_ROLE

## Properties

- Initial staking configuration only accessed by admin or operator
- Aditional staking configuration only accessed by admin or operator
- Initial Operator role defined on configuration by admin
- Registration is open to anyone, only one active registration is allowed per address
- Unregistration is open to registered stakers only and after registrationWaitTime elapsed
- Unregistration will unstake user stakes and revoke the STAKER_ROLE from address
- Staking is open only to registered stakers after registrationWaitTime elapsed
- Staking sets staker's accounting and mints a 1:1 reward token to the amount staked
- Staking updates the staking pool adding generated rewards for the period
- Unstake burns users reward token total balance and unstakes staker's Eth
- Claim Rewards is callable by anyone with current or past staked amount balance in the contract
- Claim, user stops accumulating rewards once he unstakes, but can claim the days covered in the cycle
- Slash substracts amount from staker stakes, only by admin or operator
## Install
````
forge install
````

## Test
````
forge test
````

## Coverage
````
forge coverage
````
## Deploy

### Build

```shell
$ forge build
```

### Deploy

```shell
$ forge script script/Deploy.s.sol:Deploy --rpc-url <your_rpc_url> --private-key <your_private_key>

```

