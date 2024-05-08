// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Utils} from "test/libraries/Utils.sol";

import {ConstantProductTestHarness, ConstantProduct} from "./ConstantProductTestHarness.sol";

abstract contract EnableTrading is ConstantProductTestHarness {
    function testEnableTradingDoesNotRevert() public {
        ConstantProduct.TradingParams memory defaultTradingParams = getDefaultTradingParams();
        constantProduct.enableTrading(defaultTradingParams);
    }

    function testEnableTradingRevertsIfCalledByNonManager() public {
        ConstantProduct.TradingParams memory defaultTradingParams = getDefaultTradingParams();
        vm.prank(Utils.addressFromString("this is not the owner"));
        vm.expectRevert(abi.encodeWithSelector(ConstantProduct.OnlyManagerCanCall.selector));
        constantProduct.enableTrading(defaultTradingParams);
    }

    function testEnableTradingEmitsEvent() public {
        ConstantProduct.TradingParams memory defaultTradingParams = getDefaultTradingParams();
        vm.expectEmit();
        emit ConstantProduct.TradingEnabled(constantProduct.hash(defaultTradingParams), defaultTradingParams);
        constantProduct.enableTrading(defaultTradingParams);
    }

    function testEnableTradingSetsState() public {
        ConstantProduct.TradingParams memory defaultTradingParams = getDefaultTradingParams();
        constantProduct.enableTrading(defaultTradingParams);
        assertEq(constantProduct.tradingParamsHash(), constantProduct.hash(defaultTradingParams));
    }
}
