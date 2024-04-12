// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {DeployConstantProduct} from "script/single-deployment/ConstantProduct.s.sol";

import {CowProtocolSetUp} from "./cow-protocol/CowProtocolSetUp.sol";

contract DeployConstantProductTest is Test, CowProtocolSetUp {
    DeployConstantProduct script;

    function setUp() public {
        setUpSettlementContract();

        vm.setEnv("TOKEN_0", "0x1111111111111111111111111111111111111111");
        vm.setEnv("TOKEN_1", "0x2222222222222222222222222222222222222222");

        script = new DeployConstantProduct();
    }

    function testDoesNotRevert() public {
        script.run();
    }
}
