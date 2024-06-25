// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {ConstantProductTestHarness, ConstantProduct} from "./ConstantProductTestHarness.sol";

abstract contract DisableTrading is ConstantProductTestHarness {
    function testDisableTradingDoesNotRevert() public {
        setUpDisableTrading();
        constantProduct.disableTrading();
    }

    function testDisableTradingRevertsIfCalledByNonManager() public {
        setUpDisableTrading();
        vm.prank(makeAddr("this is not the owner"));
        vm.expectRevert(abi.encodeWithSelector(ConstantProduct.OnlyManagerCanCall.selector));
        constantProduct.disableTrading();
    }

    function testDisableTradingEmitsEvent() public {
        setUpDisableTrading();
        vm.expectEmit();
        emit ConstantProduct.TradingDisabled();
        constantProduct.disableTrading();
    }

    function testDisableTradingUnsetsState() public {
        setUpDisableTrading();
        assertFalse(constantProduct.tradingEnabled() == false);
        constantProduct.disableTrading();
        assertTrue(constantProduct.tradingEnabled() == false);
    }

    // By default, trading is disabled on a newly deployed contract. Calling
    // this function enables some trade that can be disabled in a test.
    function setUpDisableTrading() private {
        constantProduct.enableTrading();
    }
}
