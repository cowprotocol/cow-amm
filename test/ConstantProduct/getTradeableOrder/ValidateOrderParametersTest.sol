// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {ConstantProductTestHarness} from "../ConstantProductTestHarness.sol";
import {ConstantProduct, GPv2Order} from "../../../src/ConstantProduct.sol";

abstract contract ValidateOrderParametersTest is ConstantProductTestHarness {
    function testValidOrderParameters() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        setUpDefaultReserves(orderOwner);
        setUpDefaultReferencePairReserves(42, 1337);

        GPv2Order.Data memory order = getTradeableOrderWrapper(orderOwner, defaultData);
        // Test all parameters with the exception of sell/buy tokens and amounts
        assertEq(order.receiver, GPv2Order.RECEIVER_SAME_AS_OWNER);
        assertEq(order.validTo, constantProduct.MAX_ORDER_DURATION());
        assertEq(order.appData, defaultData.appData);
        assertEq(order.feeAmount, 0);
        assertEq(order.kind, GPv2Order.KIND_SELL);
        assertEq(order.partiallyFillable, true);
        assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
        assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);
    }

    function testOrderValidityMovesToNextBucket() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        setUpDefaultReserves(orderOwner);
        setUpDefaultReferencePairReserves(42, 1337);

        GPv2Order.Data memory order;
        order = getTradeableOrderWrapper(orderOwner, defaultData);
        assertEq(order.validTo, constantProduct.MAX_ORDER_DURATION());

        uint256 smallOffset = 42;
        require(smallOffset < constantProduct.MAX_ORDER_DURATION());
        vm.warp(block.timestamp + constantProduct.MAX_ORDER_DURATION() + smallOffset);

        order = getTradeableOrderWrapper(orderOwner, defaultData);
        assertEq(order.validTo, 2 * constantProduct.MAX_ORDER_DURATION());
    }
}
