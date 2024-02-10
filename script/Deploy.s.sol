// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {StakeManager,IstETH} from "../src/StakeManager.sol";
import {stETH} from "../src/stETH.sol";
import {LibClone} from "@solady/utils/LibClone.sol";

contract ProxyFactory {
    function deployERC1967(uint256 value, address implementation) public returns (address instance) {
        return LibClone.deployERC1967(value, implementation);
    }
}


contract Deploy is Script {

    address constant TES_OPERTOR = address(1);
    uint128 constant UNSTAKE_PERIOD = 1 weeks;
    uint24 constant REWARD_CYCLE = 2 weeks;
    uint256 private constant REWARDS_PER_BLOCK = 10 wei;


    function setUp() public {
    }
    

    function run() public {
        vm.startBroadcast();
        stETH stkToken = new stETH();
        ProxyFactory proxyFactory = new ProxyFactory();
        StakeManager implementation = new StakeManager();
        address instanceProxy = proxyFactory.deployERC1967(0,address(implementation));
        StakeManager instance = StakeManager(instanceProxy);
        instance.initialize(REWARDS_PER_BLOCK, TES_OPERTOR, address(stkToken), UNSTAKE_PERIOD, REWARD_CYCLE);
        stkToken.transferOwnership(address(instance));
    }
}
