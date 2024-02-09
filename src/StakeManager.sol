// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@solady/utils/UUPSUpgradeable.sol";
import "./interfaces/IStakeManager.sol";
import "./interfaces/IstETH.sol";
contract StakeManager is IStakeManager, AccessControlUpgradeable,UUPSUpgradeable{

    uint256 public totalStaked;
    uint256 public lastUpdateBlock;
    uint256 public rewardsPerBlock;
    uint256 public registrationWaitTime;
    uint256 public registrationDepositAmount;
    uint256 public minimumStakeAmt;
    address public admin;
    address public operator;
    IstETH public tokenReward;

    struct Staker{
        uint256 registeredAt; // time of registration
        uint256 stakedAt; // time of un-registration
        uint256 stakeAmt; // total staked amount
    }
    mapping(address staker => Staker) stakers;

    /* ACCESS ROLES */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant STAKER_ROLE = keccak256("STAKER_ROLE");

    error InsufficientDeposit();
    error InvalidStakeMinAmt();
    error Unauthorized();
    error RegistrationDeposit();
    error AlreadyResgistered();
    error RegistrationWaitTimeNotElapsed();
    error UnregistrationError();
    error TransferFailed();

	modifier updateRewardPool() {
		totalStaked = totalStaked + _calculateRewards();
		lastUpdateBlock = block.number;
		_;
	}

    modifier OnlyAdminOrOperator() {
        require(hasRole(ADMIN_ROLE, _msgSender()) || hasRole(OPERATOR_ROLE, _msgSender()), "Only Admin or Operator");
        _;
    }

    function initialize(uint256 _rewardsPerBlock, address _operator) external initializer {
        __AccessControl_init();
        _grantRole(ADMIN_ROLE, _msgSender());
        _setRoleAdmin(OPERATOR_ROLE,ADMIN_ROLE);
        _setRoleAdmin(STAKER_ROLE,ADMIN_ROLE);
        _grantRole(OPERATOR_ROLE, _operator);
        rewardsPerBlock = _rewardsPerBlock;
    }

    /**
     * @dev Allows an admin to set the configuration of the staking contract.
     * @param _registrationDepositAmount Initial registration deposit amount in wei.
     * @param _registrationWaitTime The duration a staker must wait after initiating registration.
     */
    function setConfiguration(uint256 _registrationDepositAmount, uint256 _registrationWaitTime) external override OnlyAdminOrOperator{
        registrationWaitTime = _registrationWaitTime;
        registrationDepositAmount = _registrationDepositAmount;
    }

    /**
     * @dev Allows an account to register as a staker.
     */
    function register() external payable {
        if(stakers[msg.sender].registeredAt > 0) revert AlreadyResgistered();
        if(msg.value < registrationDepositAmount) revert RegistrationDeposit();
        stakers[msg.sender].registeredAt = block.timestamp;
    }

    /**
     * @dev Allows registered stakers to stake ether into the contract.
     */
    function stake() external payable override updateRewardPool onlyRole(STAKER_ROLE) {
        if(stakers[msg.sender].registeredAt + registrationWaitTime < block.timestamp) revert RegistrationWaitTimeNotElapsed();
        uint256 stakedAmt = msg.value;
        if(stakedAmt == 0) revert InvalidStakeMinAmt();
        stakers[msg.sender].stakeAmt += stakedAmt;
        totalStaked += stakedAmt;
        stakers[msg.sender].stakedAt = block.timestamp;
        tokenReward.mint(msg.sender,stakedAmt); // only to represent stake deposit
    }

    /**
     * @dev Allows a registered staker to unregister and exit the staking system.
     */
    function unregister() override external onlyRole(STAKER_ROLE){
        if(stakers[msg.sender].stakedAt + registrationWaitTime < block.timestamp) revert RegistrationWaitTimeNotElapsed();
        (bool success,) = _msgSender().call{value: registrationDepositAmount}('');
        if(!success) revert UnregistrationError();
        unstake();
        delete stakers[msg.sender];
    }

    /**
     * @dev Allows registered stakers to unstake their ether from the contract.
     */
    function unstake() public override updateRewardPool onlyRole(STAKER_ROLE){
        uint256 _stakeAmt = stakers[msg.sender].stakeAmt;
        uint256 userRewards = _ethToRewards(_stakeAmt);
        tokenReward.burn(msg.sender,userRewards);
        (bool succ,)=_msgSender().call{value: _stakeAmt + _rewardsToEth(userRewards) }('');
        if(!succ) revert TransferFailed();
    }

    /**
     * @dev Allows an admin to slash a portion of the staked ether of a given staker.
     * @param staker The address of the staker to be slashed.
     * @param amount The amount of ether to be slashed from the staker.
     */
    function slash(address staker, uint256 amount) external override updateRewardPool OnlyAdminOrOperator(){
        require(amount < stakers[staker].stakeAmt, "Insufficient staked amount");
        stakers[staker].stakeAmt -= amount;
        totalStaked -= amount;
    }

    function _ethToRewards(uint256 _amount) internal returns(uint256){
        uint256 rewardPool = tokenReward.totalSupply();
        uint256 stakingPool = totalStaked + _calculateRewards();
        if(rewardPool > 0 && stakingPool > 0){
            return rewardPool * _amount / stakingPool;
        }
        return _amount;
    }
    function _rewardsToEth(uint256 _amount) internal returns(uint256){
        uint256 rewardPool = tokenReward.totalSupply();
        uint256 stakingPool = totalStaked + _calculateRewards();
        return rewardPool > 0 ?  stakingPool * _amount / rewardPool : 0;
    }

    function _calculateRewards() internal view returns (uint256) {
        uint256 blocksSinceLastUpdate = block.number - lastUpdateBlock;
        return blocksSinceLastUpdate * rewardsPerBlock;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}
