// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "@solady/utils/LibClone.sol";
import "../src/StakeManager.sol";

contract StakeManagerTest is Test {
    StakeManager public stakeManager;
    ProxyFactory private proxyFactory;
    address private operator;
    uint256 constant REWARDS_RATE = 1000;

    function setUp() public {
        proxyFactory = new ProxyFactory();
        address implementation = address(new StakeManager());
        address instance = proxyFactory.deployERC1967(0, implementation);
        stakeManager = StakeManager(instance);
        stakeManager.initialize(REWARDS_RATE,operator);
    }
    function test_deployment() public {
        assert(address(stakeManager) != address(0));
        address newImpl = address(new StakeManager());
        stakeManager.upgradeToAndCall(address(newImpl), '');
    }
    function test_setConfiguration(uint256 registrationDepositAmount, uint256 registrationWaitTime) public {}
    function test_register() public {}
    function test_unregister() public {}
    function test_stake() public {}
    function test_unstake() public {}
    function test_slash(address staker, uint256 amount) public {}
}


contract ProxyFactory {
      function deployERC1967(uint256 value, address implementation)
        public
        returns (address instance){
            return LibClone.deployERC1967(value, implementation);
        }
    
}