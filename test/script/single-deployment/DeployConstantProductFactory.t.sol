// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {DeployConstantProductFactory} from "script/single-deployment/ConstantProductFactory.s.sol";

import {CowProtocolSetUp} from "./cow-protocol/CowProtocolSetUp.sol";

contract DeployConstantProductTest is Test, CowProtocolSetUp {
    DeployConstantProductFactory script;

    function setUp() public {
        setUpSettlementContract();

        script = new DeployConstantProductFactory();
    }

    function testDoesNotRevert() public {
        script.run();
    }
}
