// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Utils} from "test/libraries/Utils.sol";
import {ConstantProductTestHarness, ConstantProduct} from "./ConstantProductTestHarness.sol";

abstract contract DeploymentParamsTest is ConstantProductTestHarness {
    function testSetsSolutionSettler() public {
        require(solutionSettler != address(0), "test should use a nonzero address");
        ConstantProduct constantProduct = new ConstantProduct(solutionSettler);
        assertEq(constantProduct.solutionSettler(), solutionSettler);
    }
}
