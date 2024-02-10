// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console,console2, Vm} from "forge-std/Test.sol";
import "@solady/utils/LibClone.sol";
import {StakeManager,IstETH} from "../src/StakeManager.sol";
import "../src/stETH.sol";


contract StakeManagerTest is Test,StakeManager {
    StakeManager public instance;
    ProxyFactory private proxyFactory;

    address private TestOperator = address(1);
    uint256 private constant REWARDS_PER_BLOCK = 10 wei;
    uint256 private constant REGISTRATION_DEPOSIT = 1 ether;
    uint256 private constant REGISTRATION_WAIT_TIME = 1 weeks;
    string constant PUBLIC_RPC_ETHEREUM = "https://rpc.ankr.com/eth";
    uint256 constant FORK_BLOCK_NUM = 11191962;
    uint256 constant BLOCKS_PER_DAY = 7120;
    uint128 constant UNSTAKE_PERIOD = 1 weeks;
    uint24 constant REWARD_CYCLE = 2 weeks;

    function setUp() public {
        proxyFactory = new ProxyFactory();
        stkToken = IstETH(address(new stETH()));

        address implementation = address(new StakeManager());
        address instanceProxy = proxyFactory.deployERC1967(0, implementation);

        instance = StakeManager(instanceProxy);
        instance.initialize(REWARDS_PER_BLOCK, TestOperator, address(stkToken), UNSTAKE_PERIOD, REWARD_CYCLE);

        stkToken.transferOwnership(address(instance));

        vm.createSelectFork(PUBLIC_RPC_ETHEREUM, FORK_BLOCK_NUM);
    }

    function test_upgrade() public {
        assert(address(instance) != address(0));
        address newImpl = address(new StakeManager());
        instance.upgradeToAndCall(address(newImpl),"");
    }

    function test_setConfiguration() public {
        instance.setConfiguration(REGISTRATION_DEPOSIT, REGISTRATION_WAIT_TIME);
        assertEq(instance.registrationDepositAmount(), REGISTRATION_DEPOSIT);
        assertEq(instance.registrationWaitTime(), REGISTRATION_WAIT_TIME);
    }

    function test_setConfiguration_access() public {
        Vm.Wallet memory STAKER_1 = vm.createWallet("STAKER_1");
        vm.startPrank(STAKER_1.addr);
        vm.expectRevert("UnauthorizedError");
        instance.setConfiguration(REGISTRATION_DEPOSIT, REGISTRATION_WAIT_TIME);
    }

    function test_register() public {
        Vm.Wallet memory STAKER_1 = vm.createWallet("STAKER_1");
        _setConfiguration(REGISTRATION_DEPOSIT, REGISTRATION_WAIT_TIME);
        _register(STAKER_1, REGISTRATION_DEPOSIT);

        assert(instance.hasRole(instance.STAKER_ROLE(), STAKER_1.addr));
        assertEq(address(instance).balance, REGISTRATION_DEPOSIT);
    }
    /**
    * Unregister from the system calls unstake for the user
    */
    function test_unregister() public {
        Vm.Wallet memory STAKER_3 = vm.createWallet("STAKER_3");
        uint256 STAKE_3 = 5 ether;

        _setConfiguration(REGISTRATION_DEPOSIT, REGISTRATION_WAIT_TIME);
        _register(STAKER_3, REGISTRATION_DEPOSIT);

        // uint256 instanceBalanceB4unregister = address(instance).balance;
        vm.rollFork(block.number + BLOCKS_PER_DAY * 7);

        _stake(STAKER_3, STAKE_3);
        (uint256 stakeAmt,,,,,) = instance.stakers(STAKER_3.addr);
        assertEq(stakeAmt, STAKE_3);

        vm.rollFork(block.number + BLOCKS_PER_DAY * 7);
        _unregister(STAKER_3);

        // assert operation
        (,,,uint128 stakedAt,,) = instance.stakers(STAKER_3.addr);
        assertFalse(instance.hasRole(instance.STAKER_ROLE(), STAKER_3.addr));
        assertEq(address(instance).balance,0);
    }
    /**
        Staker is able to register and unregister without staking if needed time elapsed
     */
    function test_unregister_without_staking() public {
        Vm.Wallet memory STAKER_2 = vm.createWallet("STAKER_2");
        _setConfiguration(REGISTRATION_DEPOSIT,REGISTRATION_WAIT_TIME);
        _register(STAKER_2,REGISTRATION_DEPOSIT);

        uint256 instanceBalanceB4unregister = address(instance).balance;
        vm.warp(block.timestamp + instance.registrationWaitTime());

        _unregister(STAKER_2);

        // assert operation
        assertFalse(instance.hasRole(instance.STAKER_ROLE(), STAKER_2.addr));
        assertEq(address(instance).balance, instanceBalanceB4unregister - REGISTRATION_DEPOSIT);
    }

    function test_stake() public {
        Vm.Wallet memory STAKER_1 = vm.createWallet("STAKER_1");
        uint256 STAKE_1 = 100 ether;

        _setConfiguration(REGISTRATION_DEPOSIT, REGISTRATION_WAIT_TIME);
        _register(STAKER_1, REGISTRATION_DEPOSIT);
        // fastforwards clock to be able to stake
        vm.warp(block.timestamp + instance.registrationWaitTime());

        // stake 100 ether
        _stake(STAKER_1, STAKE_1);

        (uint256 stakeAmt,,,,,) = instance.stakers(STAKER_1.addr);
        assertEq(stakeAmt, STAKE_1);
        assertEq(address(instance).balance, REGISTRATION_DEPOSIT + STAKE_1);
    }

    function test_unstake() public {
        Vm.Wallet memory UNSTAKER = vm.createWallet("UNSTAKER");
        uint256 STAKE_AMOUNT = 0.5 ether;
        _setConfiguration(REGISTRATION_DEPOSIT, REGISTRATION_WAIT_TIME);
        _register(UNSTAKER, REGISTRATION_DEPOSIT);

        vm.warp(block.timestamp + instance.registrationWaitTime());

        _stake(UNSTAKER, STAKE_AMOUNT);

        vm.warp(block.timestamp + instance.unstakePeriod());

        vm.prank(UNSTAKER.addr);
        instance.unstake();
        assertEq(UNSTAKER.addr.balance,STAKE_AMOUNT);
        assertEq(address(instance).balance,REGISTRATION_DEPOSIT);
    }

    function test_slash() public {
        Vm.Wallet memory SLASHED = vm.createWallet("SLASHED");
        uint256 STAKE_AMOUNT = 400 ether;
        uint256 SLASH_AMOUNT = 150 ether;
        _setConfiguration(REGISTRATION_DEPOSIT, REGISTRATION_WAIT_TIME);
        _register(SLASHED, REGISTRATION_DEPOSIT);

        vm.warp(block.timestamp + instance.registrationWaitTime());
        _stake(SLASHED, STAKE_AMOUNT);

        // admin call
        instance.slash(SLASHED.addr,SLASH_AMOUNT);
        (uint256 stakeAmt,,,,,) = instance.stakers(SLASHED.addr);
        assertEq(stakeAmt, STAKE_AMOUNT - SLASH_AMOUNT);
    }

    function test_claim() public {
        Vm.Wallet memory STAKER_3 = vm.createWallet("STAKER_3");
        uint256 STAKE_3 = 1 ether;

        _setConfiguration(REGISTRATION_DEPOSIT, REGISTRATION_WAIT_TIME);
        _register(STAKER_3, REGISTRATION_DEPOSIT);
        vm.warp(block.timestamp + instance.registrationWaitTime());

        _stake(STAKER_3, STAKE_3);

        vm.warp(block.timestamp + instance.registrationWaitTime());

        vm.rollFork(block.number + BLOCKS_PER_DAY * 14);
        vm.prank(STAKER_3.addr);

        instance.claimRewards();
        // rewards compounded
        assert(stkToken.balanceOf(STAKER_3.addr) > STAKE_3);
    }

    function test_claim_after_unstaking() public {
        Vm.Wallet memory STAKER_4 = vm.createWallet("STAKER_3");
        uint256 STAKE_4 = 1 ether;

        _setConfiguration(REGISTRATION_DEPOSIT, REGISTRATION_WAIT_TIME);
        _register(STAKER_4, REGISTRATION_DEPOSIT);
        vm.warp(block.timestamp + instance.registrationWaitTime());

        _stake(STAKER_4, STAKE_4);

        vm.warp(block.timestamp + instance.registrationWaitTime());

        vm.rollFork(block.number + BLOCKS_PER_DAY * 14);
        vm.prank(STAKER_4.addr);
        instance.unstake();

        vm.rollFork(block.number + BLOCKS_PER_DAY * 7);
        vm.prank(STAKER_4.addr);
        
        instance.claimRewards();
        // Rewards of 6 days
        assertApproxEqAbs(stkToken.balanceOf(STAKER_4.addr), BLOCKS_PER_DAY * 6 * REWARDS_PER_BLOCK, 22000);
    }

    function test_ethToRewards() external{
        uint256 rwrds = _ethToRewards(1 ether);
        assertEq(rwrds, 1 ether);
    }

    /**
     *  Test helpers
     */
    function _setConfiguration(uint256 _registrationDepositAmount, uint256 _registrationWaitTime) internal {
        instance.setConfiguration(_registrationDepositAmount, _registrationWaitTime);
    }

    function _register(Vm.Wallet memory STAKER, uint256 _registrationDeposit) internal {
        vm.deal(STAKER.addr, _registrationDeposit);
        vm.prank(STAKER.addr);
        instance.register{value: _registrationDeposit}();
    }

    function _unregister(Vm.Wallet memory STAKER) internal {
        vm.prank(STAKER.addr);
        instance.unregister();
    }

    function _stake(Vm.Wallet memory STAKER, uint256 _stakeAmount) internal {
        vm.deal(STAKER.addr, _stakeAmount);
        vm.prank(STAKER.addr);
        instance.stake{value: _stakeAmount}();
    }
}

contract ProxyFactory {
    function deployERC1967(uint256 value, address implementation) public returns (address instance) {
        return LibClone.deployERC1967(value, implementation);
    }
}
