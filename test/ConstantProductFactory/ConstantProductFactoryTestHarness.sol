// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {
    ConstantProductFactory,
    ConstantProduct,
    GPv2Order,
    ISettlement,
    IERC20,
    SafeERC20
} from "src/ConstantProductFactory.sol";

import {ConstantProductTestHarness} from "test/ConstantProduct/ConstantProductTestHarness.sol";

abstract contract ConstantProductFactoryTestHarness is ConstantProductTestHarness {
    ConstantProductFactory internal constantProductFactory;
    IERC20 internal mockableToken0 = IERC20(makeAddr("ConstantProductFactoryTestHarness: mockable token 0"));
    IERC20 internal mockableToken1 = IERC20(makeAddr("ConstantProductFactoryTestHarness: mockable token 1"));

    function setUp() public virtual override(ConstantProductTestHarness) {
        super.setUp();
        constantProductFactory = new ConstantProductFactory(solutionSettler);
    }

    function mocksForTokenCreation(address constantProductAddress) internal {
        setUpTokenForDeployment(mockableToken0, constantProductAddress, address(constantProductFactory));
        setUpTokenForDeployment(mockableToken1, constantProductAddress, address(constantProductFactory));
    }
}

contract EditableOwnerConstantProductFactory is ConstantProductFactory {
    constructor(ISettlement s) ConstantProductFactory(s) {}

    function setOwner(ConstantProduct amm, address newOwner) external {
        owner[amm] = newOwner;
    }
}
