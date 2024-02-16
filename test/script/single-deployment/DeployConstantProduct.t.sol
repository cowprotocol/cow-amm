// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {CowProtocolSetUp} from "./cow-protocol/CowProtocolSetUp.sol";

import {DeployConstantProduct} from "script/single-deployment/ConstantProduct.s.sol";

contract DeployConstantProductTest is Test, CowProtocolSetUp {
    DeployConstantProduct script;

    function setUp() public {
        setUpSettlementContract();
        script = new DeployConstantProduct();
    }

    function testDoesNotRevert() public {
        script.run();
    }
}
