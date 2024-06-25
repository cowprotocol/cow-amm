// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {ConstantProductTestHarness, ConstantProduct} from "./ConstantProductTestHarness.sol";

abstract contract EnableTrading is ConstantProductTestHarness {
    function testEnableTradingDoesNotRevert() public {
        constantProduct.enableTrading();
    }

    function testEnableTradingRevertsIfCalledByNonManager() public {
        vm.prank(makeAddr("this is not the owner"));
        vm.expectRevert(abi.encodeWithSelector(ConstantProduct.OnlyManagerCanCall.selector));
        constantProduct.enableTrading();
    }

    function testEnableTradingEmitsEvent() public {
        vm.expectEmit();
        emit ConstantProduct.TradingEnabled();
        constantProduct.enableTrading();
    }

    function testEnableTradingSetsState() public {
        constantProduct.enableTrading();
        assertEq(constantProduct.tradingEnabled(), true);
    }
}
