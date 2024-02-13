// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {BalancerSetUp} from "./single-deployment/balancer/BalancerSetUp.sol";

import {DeployAllContracts} from "script/DeployAllContracts.s.sol";

contract DeployAllContractsTest is Test, BalancerSetUp {
    DeployAllContracts script;

    function setUp() public {
        setUpBalancerVault();
        script = new DeployAllContracts();
    }

    function testDoesNotRevert() public {
        script.run();
    }
}
