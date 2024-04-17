// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC1271} from "lib/openzeppelin/contracts/interfaces/IERC1271.sol";
import {IConditionalOrder} from "lib/composable-cow/src/BaseConditionalOrder.sol";

import {ConstantProductFactory, ConstantProduct, GPv2Order} from "src/ConstantProductFactory.sol";

import {Utils} from "test/libraries/Utils.sol";
import {ConstantProductFactoryTestHarness} from "./ConstantProductFactoryTestHarness.sol";

abstract contract GetTradeableOrderWithSignature is ConstantProductFactoryTestHarness {
    using GPv2Order for GPv2Order.Data;

    function testRevertsIfHandlerIsNotFactory() public {
        ConstantProduct.TradingParams memory tradingParams = getDefaultTradingParams();
        IConditionalOrder.ConditionalOrderParams memory params = IConditionalOrder.ConditionalOrderParams(
            IConditionalOrder(Utils.addressFromString("GetTradeableOrderWithSignature: not the factory")),
            keccak256("some salt"),
            abi.encode(tradingParams)
        );

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "can only handle own orders"));
        constantProductFactory.getTradeableOrderWithSignature(constantProduct, params, hex"", new bytes32[](0));
    }

    function testRevertsIfTradingWithDifferentParameters() public {
        ConstantProduct.TradingParams memory tradingParams = getDefaultTradingParams();
        setUpDefaultReserves(address(constantProduct));
        setUpDefaultReferencePairReserves(42, 1337);
        constantProduct.enableTrading(tradingParams);

        bytes32 hashEnabledParams = constantProduct.hash(tradingParams);
        ConstantProduct.TradingParams memory modifiedParams = getDefaultTradingParams();
        modifiedParams.appData = keccak256("GetTradeableOrderWithSignature: any different app data");
        bytes32 hashModifiedParams = constantProduct.hash(modifiedParams);
        require(hashEnabledParams != hashModifiedParams, "Incorrect test setup");
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid trading parameters"));
        getTradeableOrderWithSignatureWrapper(constantProduct, modifiedParams);
    }

    function testOrderMatchesTradeableOrder() public {
        ConstantProduct.TradingParams memory tradingParams = getDefaultTradingParams();
        setUpDefaultReserves(address(constantProduct));
        setUpDefaultReferencePairReserves(42, 1337);
        constantProduct.enableTrading(tradingParams);

        GPv2Order.Data memory order = checkedGetTradeableOrder(address(constantProduct), tradingParams);
        (GPv2Order.Data memory orderSigned,) = getTradeableOrderWithSignatureWrapper(constantProduct, tradingParams);
        assertEq(orderSigned.hash(bytes32(0)), order.hash(bytes32(0)));
    }

    function testSignatureIsValid() public {
        ConstantProduct.TradingParams memory tradingParams = getDefaultTradingParams();
        setUpDefaultReserves(address(constantProduct));
        setUpDefaultReferencePairReserves(42, 1337);
        constantProduct.enableTrading(tradingParams);

        (GPv2Order.Data memory order, bytes memory signature) =
            getTradeableOrderWithSignatureWrapper(constantProduct, tradingParams);
        bytes32 orderHash = order.hash(solutionSettler.domainSeparator());

        bytes4 result = constantProduct.isValidSignature(orderHash, signature);
        assertEq(result, IERC1271.isValidSignature.selector);
    }
}
