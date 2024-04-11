// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Utils} from "test/libraries/Utils.sol";

import {ConstantProductTestHarness, ConstantProduct, IERC20} from "./ConstantProductTestHarness.sol";

abstract contract DeploymentParamsTest is ConstantProductTestHarness {
    function testSetsSolutionSettler() public {
        address solutionSettler = Utils.addressFromString("DeploymentParamsTest: any solution settler");
        address token0 = Utils.addressFromString("DeploymentParamsTest: any token0");
        address token1 = Utils.addressFromString("DeploymentParamsTest: any token1");
        ConstantProduct constantProduct = new ConstantProduct(solutionSettler, IERC20(token0), IERC20(token1));
        assertEq(constantProduct.solutionSettler(), solutionSettler);
        assertEq(address(constantProduct.token0()), token0);
        assertEq(address(constantProduct.token1()), token1);
    }
}
