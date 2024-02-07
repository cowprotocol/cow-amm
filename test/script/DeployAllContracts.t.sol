// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {DeployAllContracts} from "script/DeployAllContracts.s.sol";

contract DeployAllContractsTest is Test {
    DeployAllContracts script;

    function setUp() public {
        script = new DeployAllContracts();
    }

    function testDoesNotRevert() public {
        script.run();
    }
}
