// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {DeployConstantProduct} from "script/DeployAllContracts.s.sol";

contract DeployAllContractsTest is Test {
    DeployConstantProduct script;

    function setUp() public {
        script = new DeployConstantProduct();
    }

    function testDoesNotRevert() public {
        script.run();
    }
}
