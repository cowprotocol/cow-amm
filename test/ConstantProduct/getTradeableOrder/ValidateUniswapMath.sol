// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {ConstantProductTestHarness} from "../ConstantProductTestHarness.sol";
import {ConstantProduct, GPv2Order, IConditionalOrder} from "../../../src/ConstantProduct.sol";

abstract contract ValidateUniswapMath is ConstantProductTestHarness {
    function testReturnedTradesMovesPriceToMatchUniswapLimitPrice() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        uint256 ownerReserve0 = 10 ether;
        uint256 ownerReserve1 = 10 ether;
        setUpDefaultWithReserves(orderOwner, ownerReserve0, ownerReserve1);
        setUpDefaultReferencePairReserves(1 ether, 10 ether);
        // The limit price on the reference pool is 1 token0 in exchange for 10
        // token1. The AMM is currently trading 1:1. The trade should be
        // move the AMM to match the limit price on the reference pair.
        GPv2Order.Data memory order = getTradeableOrderWrapper(orderOwner, defaultData);
        assertEq(address(order.sellToken), address(defaultData.referencePair.token0()));
        assertEq(address(order.buyToken), address(defaultData.referencePair.token1()));
        // Note: price on reference pool is 1:10.
        uint256 limitPriceAfterExecution = (ownerReserve1 + order.buyAmount) / (ownerReserve0 - order.sellAmount);
        assertEq(limitPriceAfterExecution, 10);
    }

    function testReturnedTradesMovesPriceToMatchUniswapLimitPriceOtherSide() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        uint256 ownerReserve0 = 12 ether;
        uint256 ownerReserve1 = 24 ether;
        setUpDefaultWithReserves(orderOwner, ownerReserve0, ownerReserve1);
        setUpDefaultReferencePairReserves(126 ether, 42 ether);
        // The limit price on the reference pool is 3:1. That of the order is
        // 1:2.
        GPv2Order.Data memory order = getTradeableOrderWrapper(orderOwner, defaultData);
        assertEq(address(order.sellToken), address(defaultData.referencePair.token1()));
        assertEq(address(order.buyToken), address(defaultData.referencePair.token0()));
        uint256 limitPriceAfterExecution = (ownerReserve0 + order.buyAmount) / (ownerReserve1 - order.sellAmount);
        assertEq(limitPriceAfterExecution, 3);
    }

    function testGeneratedTradeIsOptimal() public {
        // That is, the sell and buy amounts are "on the AMM curve" and can't be
        // improved by just decreasing the buy amount while satisfying the
        // restriction in `verify`.
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        // Parameters copied from testReturnedTradesMovesPriceToMatchUniswapLimitPrice
        setUpDefaultWithReserves(orderOwner, 10 ether, 10 ether);
        setUpDefaultReferencePairReserves(1 ether, 10 ether);

        GPv2Order.Data memory order = getTradeableOrderWrapper(orderOwner, defaultData);
        require(
            address(order.sellToken) == address(defaultData.referencePair.token0()),
            "this test was intended for the case sellToken == token0"
        );
        order.buyAmount = order.buyAmount - 1;
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "received amount too low"));
        verifyWrapper(orderOwner, defaultData, order);
    }

    function testGeneratedInvertedTradeIsOptimal() public {
        // This test is the same as `testGeneratedTradeIsOptimal` but with sell
        // and buy tokens inverted.
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        // Parameters copied from testReturnedTradesMovesPriceToMatchUniswapLimitPriceOtherSide
        setUpDefaultWithReserves(orderOwner, 12 ether, 24 ether);
        setUpDefaultReferencePairReserves(126 ether, 42 ether);

        GPv2Order.Data memory order = getTradeableOrderWrapper(orderOwner, defaultData);
        require(
            address(order.sellToken) == address(defaultData.referencePair.token1()),
            "this test was intended for the case sellToken == token1"
        );
        order.buyAmount = order.buyAmount - 1;
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "received amount too low"));
        verifyWrapper(orderOwner, defaultData, order);
    }

    function testGeneratedTradeWithRoundingErrors() public {
        // There are many ways to trigger a rounding error. This test only
        // considers a case where the ceil division is necessary.
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        // Parameters copied from testReturnedTradesMovesPriceToMatchUniswapLimitPrice
        uint256 roundingTrigger = 1;
        setUpDefaultWithReserves(orderOwner, 10 ether, 10 ether + roundingTrigger);
        setUpDefaultReferencePairReserves(1 ether + roundingTrigger, 10 ether);

        GPv2Order.Data memory order = getTradeableOrderWrapper(orderOwner, defaultData);
        require(
            address(order.sellToken) == address(defaultData.referencePair.token0()),
            "this test was intended for the case sellToken == token0"
        );
        verifyWrapper(orderOwner, defaultData, order);
    }

    function testGeneratedInvertedTradeWithRoundingErrors() public {
        // We also test for some rounding issues on the other side of the if
        // condition.
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        // Parameters copied from testReturnedTradesMovesPriceToMatchUniswapLimitPriceOtherSide
        uint256 roundingTrigger = 1;
        setUpDefaultWithReserves(orderOwner, 12 ether, 24 ether);
        setUpDefaultReferencePairReserves(126 ether + roundingTrigger, 42 ether);

        GPv2Order.Data memory order = getTradeableOrderWrapper(orderOwner, defaultData);
        require(
            address(order.sellToken) == address(defaultData.referencePair.token1()),
            "this test was intended for the case sellToken == token1"
        );
        verifyWrapper(orderOwner, defaultData, order);
    }
}
