// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console,Vm} from "forge-std/Test.sol";
import "@solady/utils/LibClone.sol";
import {StakeManager} from  "../src/StakeManager.sol";
import "../src/stETH.sol";

contract StakeManagerTest is Test {

    StakeManager public stakeManager;
    ProxyFactory private proxyFactory;
    address private operator;
    uint256 private constant REWARDS_RATE = 1000;
    uint256 private constant REGISTRATION_DEPOSIT = 1 ether;
    uint256 private constant REGISTRATION_WAIT_TIME = 1 weeks;
    stETH private rewardsToken;


    function setUp() public {
        proxyFactory = new ProxyFactory();
        rewardsToken = new stETH();

        address implementation = address(new StakeManager());
        address instance = proxyFactory.deployERC1967(0, implementation);

        stakeManager = StakeManager(instance);
        stakeManager.initialize(REWARDS_RATE,operator,address(rewardsToken));
        rewardsToken.transferOwnership(address(stakeManager));

        // vm.warp(block.timestamp + 200);
    }
    function test_deployment() public {
        assert(address(stakeManager) != address(0));
        address newImpl = address(new StakeManager());
        stakeManager.upgradeToAndCall(address(newImpl), '');
    }
    function test_setConfiguration() public {
        stakeManager.setConfiguration(REGISTRATION_DEPOSIT,REGISTRATION_WAIT_TIME);
        assertEq(stakeManager.registrationDepositAmount(),REGISTRATION_DEPOSIT);
        assertEq(stakeManager.registrationWaitTime(),REGISTRATION_WAIT_TIME);
    }
    function test_fail_setConfiguration() public {
        Vm.Wallet memory STAKER_1 = vm.createWallet("STAKER_1");
        vm.startPrank(STAKER_1.addr);
        vm.expectRevert("Only Admin or Operator");
        stakeManager.setConfiguration(REGISTRATION_DEPOSIT,REGISTRATION_WAIT_TIME);
    }
    function test_register() public {
        Vm.Wallet memory STAKER_1 = vm.createWallet("STAKER_1");
        _setConfiguration(REGISTRATION_DEPOSIT,REGISTRATION_WAIT_TIME);
        _register(STAKER_1,REGISTRATION_DEPOSIT);
        assert(stakeManager.hasRole(stakeManager.STAKER_ROLE(), STAKER_1.addr));
        assertEq(address(stakeManager).balance,REGISTRATION_DEPOSIT);
    }
    function test_unregister() public {
        Vm.Wallet memory STAKER_2 = vm.createWallet("STAKER_2");
        _setConfiguration(REGISTRATION_DEPOSIT,REGISTRATION_WAIT_TIME);
        _register(STAKER_2,REGISTRATION_DEPOSIT);
        _unregister(STAKER_2);
    }

    function test_stake() public {
        Vm.Wallet memory STAKER_1 = vm.createWallet("STAKER_1");
        uint256 STAKE_1 = 100 ether;
        
        _setConfiguration(REGISTRATION_DEPOSIT,REGISTRATION_WAIT_TIME);
        _register(STAKER_1,REGISTRATION_DEPOSIT);
        // fastforwards clock to be able to stake
        vm.warp(block.timestamp + stakeManager.registrationWaitTime());
        
        // stake 100 ether
        _stake(STAKER_1,STAKE_1);

        (,,uint256 stakeAmt) = stakeManager.stakers(STAKER_1.addr);
        assertEq(stakeAmt,STAKE_1);
        assertEq(address(stakeManager).balance,REGISTRATION_DEPOSIT + STAKE_1);
    }

    function test_unstake() public {}
    function test_slash(address staker, uint256 amount) public {}

    /**
        Internal test helpers
     */
    function _setConfiguration(uint256 _registrationDepositAmount, uint256 _registrationWaitTime) internal{
        stakeManager.setConfiguration(_registrationDepositAmount, _registrationWaitTime);
    }
    function _register(Vm.Wallet memory STAKER, uint256 _registrationDeposit) internal {
        vm.deal(STAKER.addr, _registrationDeposit);
        vm.prank(STAKER.addr);
        stakeManager.register{value: _registrationDeposit}();
    }
    function _unregister(Vm.Wallet memory STAKER) internal {
        vm.prank(STAKER.addr);
        stakeManager.unregister();
    }
    function _stake(Vm.Wallet memory STAKER, uint256 _stakeAmount) internal {
        vm.deal(STAKER.addr, _stakeAmount);
        vm.prank(STAKER.addr);
        stakeManager.stake{value: _stakeAmount}();
    }
    

}

contract ProxyFactory {
      function deployERC1967(uint256 value, address implementation)
        public
        returns (address instance){
            return LibClone.deployERC1967(value, implementation);
        }
    
}