// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@solady/utils/UUPSUpgradeable.sol";
import "./interfaces/IStakeManager.sol";
import "./interfaces/IstETH.sol";

contract StakeManager is IStakeManager, AccessControlUpgradeable, UUPSUpgradeable {
    using Cast for uint256;

    // Access roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant STAKER_ROLE = keccak256("STAKER_ROLE");

    // ERC20 mintable Reward token
    IstETH  public stkToken;
    uint256 public totalStaked;
    uint256 public rewardsPerBlock;
    uint256 public registrationWaitTime;
    uint256 public registrationDepositAmount;
    uint128 public lastUpdateBlock;
    uint128 public unstakePeriod;
    uint24  public rewardsWeeksCycle;

    // Staker interactions to track
    struct Staker {
        uint256 stakeAmt; // total staked amount
        uint256 claimedAmt; // claimed amount
        uint128 registeredAt; // time of registration
        uint128 stakedAt; // time of un-registration
        uint128 unstakedAt; // time of registration
        uint128 claimedAt; // time of last claim
    }

    // stakers accounting
    mapping(address staker => Staker) public stakers;

    event Registration(address _staker);
    event UpdateConfiguration(address _operator);
    event Unregistration(address _staker);
    event Stake(address _staker);
    event Unstake(address _staker);
    event ClaimRewards(address _staker);
    event Slash(address _staker);


    error InvalidStakeAmtError();
    error UnauthorizedError();
    error InvalidRegisterAmountError();
    error SecondResgisteredError();
    error RegisterWaitTimeError();
    error UnregistrationError();
    error TransferFailedError();
    error MinRewardCycleError();
    error UnstakePeriodError();
    error NoStakeAvalableError();
    error NothingToClaimError();

    /**
    * @dev Updates staking pool, adds rewards on blocks elapsed
    */
    modifier _updateRewardPool() {
        totalStaked = totalStaked + _calculateRewards();
        lastUpdateBlock = block.number.u128();
        _;
    }

    modifier OnlyAdminOrOperator() {
        require(hasRole(ADMIN_ROLE, _msgSender()) || hasRole(OPERATOR_ROLE, _msgSender()), "UnauthorizedError");
        _;
    }

    /**
     * @dev Allows an admin to set initial configuration of the staking contract.
     * @dev initializes access control
     * @param _rewardsPerBlock rewards rate
     * @param _operator aditional rol to access contract config
     * @param _stkToken reward token to represent stake deposit in 1:1 ratio
     * @param _unstakePeriod minimum staking period to unstake
     * @param _rewardWeeksCycle cycle to claim rewards
     */
    function initialize(
        uint256 _rewardsPerBlock,
        address _operator,
        address _stkToken,
        uint128 _unstakePeriod,
        uint24 _rewardWeeksCycle
    ) external initializer {
        __AccessControl_init();
        _grantRole(ADMIN_ROLE, _msgSender());
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(STAKER_ROLE, ADMIN_ROLE);
        _grantRole(OPERATOR_ROLE, _operator);
        rewardsPerBlock = _rewardsPerBlock;
        stkToken = IstETH(_stkToken);
        unstakePeriod = _unstakePeriod;
        rewardsWeeksCycle = _rewardWeeksCycle;
    }
    /**
     * @dev Allows an admin to set the configuration of the staking contract.j
     * @param _registrationDepositAmount Initixal registration deposit amount in wei.
     * @param _registrationWaitTime The duration a staker must wait after initiating registration.
     */

    function setConfiguration(uint256 _registrationDepositAmount, uint256 _registrationWaitTime)
        external
        override
        OnlyAdminOrOperator
    {
        registrationWaitTime = _registrationWaitTime;
        registrationDepositAmount = _registrationDepositAmount;
        emit UpdateConfiguration(_msgSender());
    }

    /**
     * @dev Allows an account to register as a staker.
     */
    function register() external payable {
        if (stakers[_msgSender()].registeredAt > 0) revert SecondResgisteredError();
        if (msg.value < registrationDepositAmount) revert InvalidRegisterAmountError();
        stakers[_msgSender()].registeredAt = block.timestamp.u128();
        _grantRole(STAKER_ROLE, _msgSender());
        emit Registration(_msgSender());
    }
    /**
     * @dev Allows a registered staker to unregister and exit the staking system.
     */
    function unregister() external override onlyRole(STAKER_ROLE) {
        if (stakers[_msgSender()].registeredAt + registrationWaitTime > block.timestamp.u128()) {
            revert RegisterWaitTimeError();
        }
        (bool success,) = _msgSender().call{value: registrationDepositAmount}("");
        if (!success) revert UnregistrationError();
        unstake();
        _revokeRole(STAKER_ROLE, _msgSender());
        emit Unregistration(_msgSender());
    }

    /**
     * @dev Allows registered stakers to stake ether into the contract.
     */
    function stake() external payable override _updateRewardPool onlyRole(STAKER_ROLE) {
        if (stakers[_msgSender()].registeredAt + registrationWaitTime > block.timestamp.u128()) {
            revert RegisterWaitTimeError();
        }
        uint256 stakedAmount = msg.value;
        if (stakedAmount == 0) revert InvalidStakeAmtError();
        stakers[_msgSender()].stakeAmt += stakedAmount;
        totalStaked += stakedAmount;
        stakers[_msgSender()].stakedAt = block.timestamp.u128();
        stkToken.mint(_msgSender(), _ethToRewards(stakedAmount));
        emit Stake(_msgSender());
    }

    /**
     * @dev Allows registered stakers to unstake their ether from the contract.
     */
    function unstake() public override _updateRewardPool onlyRole(STAKER_ROLE) {
        Staker memory staker = stakers[_msgSender()];

        // staker.stakeAmt reseted after claiming
        if (staker.unstakedAt > 0) revert NoStakeAvalableError();

        if (staker.stakedAt + unstakePeriod > block.timestamp.u128()) revert UnstakePeriodError();

        uint256 _stakeAmt = staker.stakeAmt;

        stkToken.burn(_msgSender(), stkToken.balanceOf(_msgSender()));

        (bool succ,) = _msgSender().call{value: _stakeAmt}("");
        if (!succ) revert TransferFailedError();
        stakers[_msgSender()].unstakedAt = block.number.u128();
        emit Unstake(_msgSender());
    }

    /**
     * @dev Allows claiming of rewards within the claiming cycle.
     */
    function claimRewards() external {
        Staker memory staker = stakers[_msgSender()];
        if(staker.stakeAmt == 0) revert NothingToClaimError();
        if(staker.claimedAt + rewardsWeeksCycle > block.timestamp.u128()) revert MinRewardCycleError();

        // user stops accumulating rewards once he unstakes, but can claim the days covered in the cycle
        uint256 periodSync;
        if (staker.unstakedAt > 0) {
            periodSync = block.number.u128() - staker.unstakedAt;
            stakers[_msgSender()].stakeAmt = 0;
        }

        uint256 toClaim = _calculateRewards() - periodSync;
        stkToken.mint(_msgSender(), toClaim - staker.claimedAmt);
        staker.claimedAt = block.timestamp.u128();
        staker.claimedAmt = toClaim;
        emit ClaimRewards(_msgSender());
    }

    /**
     * @dev Allows an admin to slash a portion of the staked ether of a given staker.
     * @param staker The address of the staker to be slashed.
     * @param amount The amount of ether to be slashed from the staker.
     */
    function slash(address staker, uint256 amount) external override _updateRewardPool OnlyAdminOrOperator {
        require(amount < stakers[staker].stakeAmt, "Insufficient staked amount");
        stakers[staker].stakeAmt -= amount;
        totalStaked -= amount;
        emit Slash(_msgSender());
    }

    /**
     * @dev Calculates eth amount to rewards
     * @param _amount eth amount to convert
     */
    function _ethToRewards(uint256 _amount) internal view returns (uint256) {
        uint256 rewardPool = stkToken.totalSupply();
        uint256 stakingPool = totalStaked + _calculateRewards();
        if (rewardPool > 0 && stakingPool > 0) {
            return (rewardPool * _amount / stakingPool);
        }
        return _amount;
    }

    /**
     * @dev Calculates rewards since last time staking pool was updated
     */
    function _calculateRewards() internal view returns (uint256) {
        uint256 blocksSinceLastUpdate = block.number - lastUpdateBlock;
        return blocksSinceLastUpdate * rewardsPerBlock;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}

library Cast {
    error CastOverflow();
    function u128(uint256 x) internal pure returns (uint128 y) {
        if(x >= type(uint128).max)revert CastOverflow();
        y = uint128(x);
    }
}
