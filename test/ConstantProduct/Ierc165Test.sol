// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ConstantProductTestHarness} from "./ConstantProductTestHarness.sol";
import {IConditionalOrderGenerator, IERC165} from "src/ConstantProduct.sol";

abstract contract Ierc165Test is ConstantProductTestHarness {
    function testSupportsIConditionalOrderGenerator() public {
        assertTrue(constantProduct.supportsInterface(type(IConditionalOrderGenerator).interfaceId));
    }

    function testSupportsIerc165() public {
        assertTrue(constantProduct.supportsInterface(type(IERC165).interfaceId));
    }

    function testReturnsFalseForArbitraryId() public {
        assertFalse(constantProduct.supportsInterface(0x13371337));
    }
}
