// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {ConstantProduct, GPv2Order, IERC20, IConditionalOrder} from "src/ConstantProduct.sol";

import {ConstantProductTestHarness} from "../ConstantProductTestHarness.sol";

abstract contract ValidateOrderParametersTest is ConstantProductTestHarness {
    function setUpBasicOrder() internal returns (GPv2Order.Data memory defaultOrder) {
        setUpDefaultPair();
        setUpDefaultReserves(address(constantProduct));
        setUpDefaultCommitment();
        defaultOrder = getDefaultOrder();
    }

    function testDefaultDoesNotRevert() public {
        GPv2Order.Data memory defaultOrder = setUpBasicOrder();

        constantProduct.verify(defaultOrder);
    }

    function testCanInvertTokens() public {
        GPv2Order.Data memory defaultOrder = setUpBasicOrder();

        (defaultOrder.sellToken, defaultOrder.buyToken) = (defaultOrder.buyToken, defaultOrder.sellToken);
        constantProduct.verify(defaultOrder);
    }

    function testRevertsIfInvalidTokenCombination() public {
        GPv2Order.Data memory defaultOrder = setUpBasicOrder();

        IERC20 badToken = IERC20(makeAddr("bad token"));
        vm.mockCall(address(badToken), abi.encodeCall(IERC20.balanceOf, (address(constantProduct))), abi.encode(1337));
        IERC20 badTokenExtra = IERC20(makeAddr("extra bad token"));
        vm.mockCall(
            address(badTokenExtra), abi.encodeCall(IERC20.balanceOf, (address(constantProduct))), abi.encode(1337)
        );

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
            constantProduct.verify(defaultOrder);
        }

        for (uint256 i = 0; i < buyTokenInvalidCombinations.length; i += 1) {
            defaultOrder.sellToken = buyTokenInvalidCombinations[i][0];
            defaultOrder.buyToken = buyTokenInvalidCombinations[i][1];

            vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid buy token"));
            constantProduct.verify(defaultOrder);
        }
    }

    function testRevertsIfDifferentReceiver() public {
        GPv2Order.Data memory defaultOrder = setUpBasicOrder();

        defaultOrder.receiver = makeAddr("bad receiver");
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "receiver must be zero address")
        );
        constantProduct.verify(defaultOrder);
    }

    function testRevertsIfExpiresFarInTheFuture() public {
        GPv2Order.Data memory defaultOrder = setUpBasicOrder();

        defaultOrder.validTo = uint32(block.timestamp) + constantProduct.MAX_ORDER_DURATION() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "validity too far in the future")
        );
        constantProduct.verify(defaultOrder);
    }

    function testRevertsIfDifferentAppData() public {
        GPv2Order.Data memory defaultOrder = setUpBasicOrder();

        defaultOrder.appData = keccak256(bytes("bad app data"));
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid appData"));
        constantProduct.verify(defaultOrder);
    }

    function testRevertsIfNonzeroFee() public {
        GPv2Order.Data memory defaultOrder = setUpBasicOrder();

        defaultOrder.feeAmount = 1;
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "fee amount must be zero"));
        constantProduct.verify(defaultOrder);
    }

    function testRevertsIfSellTokenBalanceIsNotErc20() public {
        GPv2Order.Data memory defaultOrder = setUpBasicOrder();

        defaultOrder.sellTokenBalance = GPv2Order.BALANCE_EXTERNAL;
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "sellTokenBalance must be erc20")
        );
        constantProduct.verify(defaultOrder);
    }

    function testRevertsIfBuyTokenBalanceIsNotErc20() public {
        GPv2Order.Data memory defaultOrder = setUpBasicOrder();

        defaultOrder.buyTokenBalance = GPv2Order.BALANCE_EXTERNAL;
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "buyTokenBalance must be erc20")
        );
        constantProduct.verify(defaultOrder);
    }
}
