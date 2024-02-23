// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ConstantProduct, GPv2Order} from "src/ConstantProduct.sol";

import {ConstantProductTestHarness} from "../ConstantProductTestHarness.sol";

abstract contract ValidateUniswapMath is ConstantProductTestHarness {
    function testReturnedTradeValues() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        uint256 ownerReserve0 = 10 ether;
        uint256 ownerReserve1 = 10 ether;
        setUpDefaultWithReserves(orderOwner, ownerReserve0, ownerReserve1);
        setUpDefaultReferencePairReserves(1 ether, 10 ether);
        GPv2Order.Data memory order = getTradeableOrderWrapper(orderOwner, defaultData);

        assertEq(address(order.sellToken), address(defaultData.token0));
        assertEq(address(order.buyToken), address(defaultData.token1));

        // Assert explicit amounts to see that the trade is reasonable.
        assertEq(order.sellAmount, 4.5 ether);
        assertEq(order.buyAmount, 24.75 ether);
    }

    function testReturnedTradeValuesOtherSide() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        uint256 ownerReserve0 = 12 ether;
        uint256 ownerReserve1 = 24 ether;
        setUpDefaultWithReserves(orderOwner, ownerReserve0, ownerReserve1);
        setUpDefaultReferencePairReserves(126 ether, 42 ether);
        // The limit price on the reference pool is 3:1. That of the order is
        // 1:2.

        GPv2Order.Data memory order = getTradeableOrderWrapper(orderOwner, defaultData);
        assertEq(address(order.sellToken), address(defaultData.token1));
        assertEq(address(order.buyToken), address(defaultData.token0));

        // Assert explicit amounts to see that the trade is reasonable.
        assertEq(order.sellAmount, 10 ether);
        assertEq(order.buyAmount, 17.5 ether);
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
            address(order.sellToken) == address(defaultData.token0),
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
            address(order.sellToken) == address(defaultData.token1),
            "this test was intended for the case sellToken == token1"
        );
        verifyWrapper(orderOwner, defaultData, order);
    }
}
