// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {ConstantProduct, ConstantProductFactory, IPriceOracle} from "src/ConstantProductFactory.sol";

import {ConstantProductFactoryTestHarness} from "./ConstantProductFactoryTestHarness.sol";

abstract contract DisableTrading is ConstantProductFactoryTestHarness {
    function testOnlyOwnerCanDisableTrading() public {
        address notTheOwner = makeAddr("some address that isn't the owner");
        ConstantProduct amm = setupAndCreateAMM();
        require(constantProductFactory.owner(amm) != notTheOwner, "bad test setup");

        vm.expectRevert(abi.encodeWithSelector(ConstantProductFactory.OnlyOwnerCanCall.selector, address(this)));
        vm.prank(notTheOwner);
        constantProductFactory.disableTrading(amm);
    }

    function testResetsTradingState() public {
        ConstantProduct amm = setupAndCreateAMM();

        constantProductFactory.disableTrading(amm);
        assertEq(amm.tradingEnabled(), false);
    }

    function testDisableTradingEmitsExpectedEvents() public {
        ConstantProduct amm = setupAndCreateAMM();

        vm.expectEmit();
        emit ConstantProductFactory.TradingDisabled(amm);
        constantProductFactory.disableTrading(amm);
    }

    function setupAndCreateAMM() private returns (ConstantProduct) {
        uint256 amount0 = 1234;
        uint256 amount1 = 5678;
        mocksForTokenCreation(
            constantProductFactory.ammDeterministicAddress(address(this), mockableToken0, mockableToken1)
        );
        return constantProductFactory.create(mockableToken0, amount0, mockableToken1, amount1);
    }
}
