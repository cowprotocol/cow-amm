// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {ConstantProductTestHarness} from "../ConstantProductTestHarness.sol";
import {ConstantProduct, GPv2Order, IERC20, IConditionalOrder} from "../../../src/ConstantProduct.sol";

abstract contract ValidateOrderParametersTest is ConstantProductTestHarness {
    function testDefaultDoesNotRevert() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        setUpDefaultReserves(orderOwner);

        GPv2Order.Data memory defaultOrder = getDefaultOrder();

        verifyWrapper(orderOwner, defaultData, defaultOrder);
    }

    function testCanInvertTokens() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        setUpDefaultReserves(orderOwner);

        GPv2Order.Data memory defaultOrder = getDefaultOrder();
        (defaultOrder.sellToken, defaultOrder.buyToken) = (defaultOrder.buyToken, defaultOrder.sellToken);

        verifyWrapper(orderOwner, defaultData, defaultOrder);
    }

    function testRevertsIfInvalidTokenCombination() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        setUpDefaultReserves(orderOwner);
        IERC20 badToken = IERC20(addressFromString("bad token"));
        vm.mockCall(address(badToken), abi.encodeWithSelector(IERC20.balanceOf.selector, orderOwner), abi.encode(1337));
        IERC20 badTokenExtra = IERC20(addressFromString("extra bad token"));
        vm.mockCall(
            address(badTokenExtra), abi.encodeWithSelector(IERC20.balanceOf.selector, orderOwner), abi.encode(1337)
        );

        GPv2Order.Data memory defaultOrder = getDefaultOrder();
        IERC20[2][4] memory sellTokenInvalidCombinations = [
            [badToken, badToken],
            [badToken, defaultOrder.sellToken],
            [badToken, defaultOrder.buyToken],
            [badToken, badTokenExtra]
        ];
        IERC20[2][4] memory buyTokenInvalidCombinations = [
            [defaultOrder.sellToken, defaultOrder.sellToken],
            [defaultOrder.buyToken, defaultOrder.buyToken],
            [defaultOrder.sellToken, badToken],
            [defaultOrder.buyToken, badToken]
        ];

        for (uint256 i = 0; i < sellTokenInvalidCombinations.length; i += 1) {
            defaultOrder.sellToken = sellTokenInvalidCombinations[i][0];
            defaultOrder.buyToken = sellTokenInvalidCombinations[i][1];

            vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid sell token"));
            verifyWrapper(orderOwner, defaultData, defaultOrder);
        }

        for (uint256 i = 0; i < buyTokenInvalidCombinations.length; i += 1) {
            defaultOrder.sellToken = buyTokenInvalidCombinations[i][0];
            defaultOrder.buyToken = buyTokenInvalidCombinations[i][1];

            vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid buy token"));
            verifyWrapper(orderOwner, defaultData, defaultOrder);
        }
    }

    function testRevertsIfDifferentReceiver() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        setUpDefaultReserves(orderOwner);

        GPv2Order.Data memory defaultOrder = getDefaultOrder();
        defaultOrder.receiver = addressFromString("bad receiver");

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid receiver"));
        verifyWrapper(orderOwner, defaultData, defaultOrder);
    }

    function testRevertsIfExpiresFarInTheFuture() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        setUpDefaultReserves(orderOwner);

        GPv2Order.Data memory defaultOrder = getDefaultOrder();
        defaultOrder.validTo = uint32(block.timestamp) + constantProduct.MAX_ORDER_DURATION() + 1;

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid validTo"));
        verifyWrapper(orderOwner, defaultData, defaultOrder);
    }

    function testRevertsIfDifferentAppData() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        setUpDefaultReserves(orderOwner);

        GPv2Order.Data memory defaultOrder = getDefaultOrder();
        defaultOrder.appData = keccak256(bytes("bad app data"));

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid appData"));
        verifyWrapper(orderOwner, defaultData, defaultOrder);
    }

    function testRevertsIfNonzeroFee() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        setUpDefaultReserves(orderOwner);

        GPv2Order.Data memory defaultOrder = getDefaultOrder();
        defaultOrder.feeAmount = 1;

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid feeAmount"));
        verifyWrapper(orderOwner, defaultData, defaultOrder);
    }

    function testRevertsIfSellTokenBalanceIsNotErc20() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        setUpDefaultReserves(orderOwner);

        GPv2Order.Data memory defaultOrder = getDefaultOrder();
        defaultOrder.sellTokenBalance = GPv2Order.BALANCE_EXTERNAL;

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid sellTokenBalance"));
        verifyWrapper(orderOwner, defaultData, defaultOrder);
    }

    function testRevertsIfBuyTokenBalanceIsNotErc20() public {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        setUpDefaultReserves(orderOwner);

        GPv2Order.Data memory defaultOrder = getDefaultOrder();
        defaultOrder.buyTokenBalance = GPv2Order.BALANCE_EXTERNAL;

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid buyTokenBalance"));
        verifyWrapper(orderOwner, defaultData, defaultOrder);
    }
}
