// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ConstantProduct, GPv2Order} from "src/ConstantProduct.sol";
import {IWatchtowerCustomErrors} from "src/interfaces/IWatchtowerCustomErrors.sol";

import {ConstantProductTestHarness} from "../ConstantProductTestHarness.sol";

abstract contract ValidateOrderParametersTest is ConstantProductTestHarness {
    function testValidOrderParameters() public {
        ConstantProduct.Data memory defaultData = getDefaultData();
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
        ConstantProduct.Data memory defaultData = getDefaultData();
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

    function testRevertsIfAmountTooLowOnSellToken() public {
        ConstantProduct.Data memory defaultData = getDefaultData();
        setUpDefaultReserves(orderOwner);
        setUpDefaultReferencePairReserves(42, 1337);

        uint256 currentBlock = 1337;
        vm.roll(currentBlock);

        GPv2Order.Data memory order = getTradeableOrderWrapper(orderOwner, defaultData);
        require(order.sellToken == defaultData.token0, "test was design for token0 to be the sell token");
        defaultData.minTradedToken0 = order.sellAmount;
        order = getTradeableOrderWrapper(orderOwner, defaultData);
        defaultData.minTradedToken0 = order.sellAmount + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IWatchtowerCustomErrors.PollTryAtBlock.selector, currentBlock + 1, "traded amount too small"
            )
        );
        getTradeableOrderUncheckedWrapper(orderOwner, defaultData);
    }

    function testRevertsIfAmountTooLowOnBuyToken() public {
        ConstantProduct.Data memory defaultData = getDefaultData();
        setUpDefaultReserves(orderOwner);
        setUpDefaultReferencePairReserves(1337, 42);

        uint256 currentBlock = 1337;
        vm.roll(currentBlock);

        GPv2Order.Data memory order = getTradeableOrderWrapper(orderOwner, defaultData);
        require(order.buyToken == defaultData.token0, "test was design for token0 to be the buy token");
        defaultData.minTradedToken0 = order.buyAmount;
        order = getTradeableOrderWrapper(orderOwner, defaultData);
        defaultData.minTradedToken0 = order.buyAmount + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IWatchtowerCustomErrors.PollTryAtBlock.selector, currentBlock + 1, "traded amount too small"
            )
        );
        getTradeableOrderUncheckedWrapper(orderOwner, defaultData);
    }

    function testSellAmountSubtractionUnderflow() public {
        ConstantProduct.Data memory defaultData = getDefaultData();
        (uint256 selfReserve0, uint256 selfReserve1) = (1337, 1337);
        (uint256 uniswapReserve0, uint256 uniswapReserve1) = (1, 1);
        setUpDefaultWithReserves(orderOwner, selfReserve0, selfReserve1);
        setUpDefaultReferencePairReserves(uniswapReserve0, uniswapReserve1);

        uint256 currentBlock = 1337;
        vm.roll(currentBlock);

        vm.expectRevert(
            abi.encodeWithSelector(
                IWatchtowerCustomErrors.PollTryAtBlock.selector, currentBlock + 1, "subtraction underflow"
            )
        );
        getTradeableOrderUncheckedWrapper(orderOwner, defaultData);
    }
}
