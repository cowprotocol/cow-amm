// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Utils} from "test/libraries/Utils.sol";

import {ConstantProductTestHarness, ConstantProduct} from "./ConstantProductTestHarness.sol";

abstract contract DisableTrading is ConstantProductTestHarness {
    function testDisableTradingDoesNotRevert() public {
        setUpDisableTrading();
        constantProduct.disableTrading();
    }

    function testDisableTradingRevertsIfCalledByNonManager() public {
        setUpDisableTrading();
        vm.prank(Utils.addressFromString("this is not the owner"));
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
        assertFalse(constantProduct.tradingParamsHash() == constantProduct.NO_TRADING());
        constantProduct.disableTrading();
        assertTrue(constantProduct.tradingParamsHash() == constantProduct.NO_TRADING());
    }

    function setUpDisableTrading() private {
        ConstantProduct.TradingParams memory defaultTradingParams = getDefaultTradingParams();
        constantProduct.enableTrading(defaultTradingParams);
    }
}