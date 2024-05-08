// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {BalancerSetUp} from "./single-deployment/balancer/BalancerSetUp.sol";
import {CowProtocolSetUp} from "./single-deployment/cow-protocol/CowProtocolSetUp.sol";

import {DeployAllContracts} from "script/DeployAllContracts.s.sol";

contract DeployAllContractsTest is Test, BalancerSetUp, CowProtocolSetUp {
    DeployAllContracts script;

    function setUp() public {
        setUpSettlementContract();
        setUpComposableCowContract();
        setUpBalancerVault();

        script = new DeployAllContracts();
    }

    function testDoesNotRevert() public {
        script.run();
    }
}
