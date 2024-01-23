// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "lib/composable-cow/lib/@openzeppelin/contracts/interfaces/IERC20.sol";
import {BaseComposableCoWTest} from "lib/composable-cow/test/ComposableCoW.base.t.sol";

import {ConstantProduct} from "../src/ConstantProduct.sol";

contract E2eCounterTest is BaseComposableCoWTest {
    ConstantProduct constantProduct;
    address safe;

    function setUp() public virtual override(BaseComposableCoWTest) {
        super.setUp();

        constantProduct = new ConstantProduct();
    }
}

