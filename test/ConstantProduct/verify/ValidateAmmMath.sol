// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {ConstantProductTestHarness} from "../ConstantProductTestHarness.sol";
import {ConstantProduct, GPv2Order, IUniswapV2Pair, IERC20, IConditionalOrder} from "../../../src/ConstantProduct.sol";

abstract contract ValidateAmmMath is ConstantProductTestHarness {
    IUniswapV2Pair pair = IUniswapV2Pair(addressFromString("pair for math verification"));

    function setUpAmmWithReserves(uint256 amountToken0, uint256 amountToken1) internal {
        IERC20 token0 = IERC20(addressFromString("token0 for math verification"));
        IERC20 token1 = IERC20(addressFromString("token1 for math verification"));
        vm.mockCall(address(pair), abi.encodeWithSelector(IUniswapV2Pair.token0.selector), abi.encode(token0));
        vm.mockCall(address(pair), abi.encodeWithSelector(IUniswapV2Pair.token1.selector), abi.encode(token1));
        // Reverts for everything else
        vm.mockCallRevert(address(pair), hex"", abi.encode("Called unexpected function on mock pair"));
        require(pair.token0() != pair.token1(), "Pair setup failed: should use distinct tokens");

        vm.mockCall(
            address(token0), abi.encodeWithSelector(IERC20.balanceOf.selector, orderOwner), abi.encode(amountToken0)
        );
        vm.mockCall(
            address(token1), abi.encodeWithSelector(IERC20.balanceOf.selector, orderOwner), abi.encode(amountToken1)
        );
    }

    function setUpOrderWithReserves(uint256 amountToken0, uint256 amountToken1)
        internal
        returns (ConstantProduct.Data memory data, GPv2Order.Data memory order)
    {
        setUpAmmWithReserves(amountToken0, amountToken1);
        order = getDefaultOrder();
        order.sellToken = IERC20(pair.token0());
        order.buyToken = IERC20(pair.token1());
        order.sellAmount = 0;
        order.buyAmount = 0;

        data = ConstantProduct.Data(pair, order.appData);
    }

    // Note: if X is the reserve of the token that is taken from the AMM, and Y
    // the reserve of the token that is deposited into the AMM, then given any
    // in amount x you can compute the out amount for a constant-product AMM as:
    //         Y * x
    //   y = ---------
    //         X - x
    function getExpectedAmountIn(uint256[2] memory reserves, uint256 amountOut) internal pure returns (uint256) {
        uint256 poolIn = reserves[0];
        uint256 poolOut = reserves[1];
        return poolIn * amountOut / (poolOut - amountOut);
    }

    function testExactAmountsInOut() public {
        uint256 poolOut = 1100 ether;
        uint256 poolIn = 10 ether;
        (ConstantProduct.Data memory data, GPv2Order.Data memory order) = setUpOrderWithReserves(poolOut, poolIn);

        uint256 amountOut = 100 ether;
        uint256 amountIn = getExpectedAmountIn([poolIn, poolOut], amountOut);
        order.sellAmount = amountOut;
        order.buyAmount = amountIn;

        verifyWrapper(orderOwner, data, order);

        // The next line is there so that we can see at a glance that the out
        // amount is reasonable given the in amount, since the math could be
        // hiding the fact that the AMM leads to bad orders.
        require(amountIn == 1 ether, "amount in was not updated");
    }

    function testOneTooMuchOut() public {
        uint256 poolOut = 1100 ether;
        uint256 poolIn = 10 ether;
        (ConstantProduct.Data memory data, GPv2Order.Data memory order) = setUpOrderWithReserves(poolOut, poolIn);

        uint256 amountOut = 100 ether;
        uint256 amountIn = getExpectedAmountIn([poolIn, poolOut], amountOut);
        order.sellAmount = amountOut + 1;
        order.buyAmount = amountIn;

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "received amount too low"));
        verifyWrapper(orderOwner, data, order);
    }

    function testOneTooLittleIn() public {
        uint256 poolOut = 1100 ether;
        uint256 poolIn = 10 ether;
        (ConstantProduct.Data memory data, GPv2Order.Data memory order) = setUpOrderWithReserves(poolOut, poolIn);

        uint256 amountOut = 100 ether;
        uint256 amountIn = getExpectedAmountIn([poolIn, poolOut], amountOut);
        order.sellAmount = amountOut;
        order.buyAmount = amountIn - 1;

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "received amount too low"));
        verifyWrapper(orderOwner, data, order);
    }

    function testInvertInOutToken() public {
        uint256 poolOut = 1100 ether;
        uint256 poolIn = 10 ether;
        (ConstantProduct.Data memory data, GPv2Order.Data memory order) = setUpOrderWithReserves(poolIn, poolOut);

        uint256 amountOut = 100 ether;
        uint256 amountIn = getExpectedAmountIn([poolIn, poolOut], amountOut);
        (order.sellToken, order.buyToken) = (order.buyToken, order.sellToken);
        order.sellAmount = amountOut;
        order.buyAmount = amountIn;

        verifyWrapper(orderOwner, data, order);
    }

    function testInvertedTokenOneTooMuchOut() public {
        uint256 poolOut = 1100 ether;
        uint256 poolIn = 10 ether;
        (ConstantProduct.Data memory data, GPv2Order.Data memory order) = setUpOrderWithReserves(poolIn, poolOut);

        uint256 amountOut = 100 ether;
        uint256 amountIn = getExpectedAmountIn([poolIn, poolOut], amountOut);
        (order.sellToken, order.buyToken) = (order.buyToken, order.sellToken);
        order.sellAmount = amountOut + 1;
        order.buyAmount = amountIn;

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "received amount too low"));
        verifyWrapper(orderOwner, data, order);
    }

    function testInvertedTokensOneTooLittleIn() public {
        uint256 poolOut = 1100 ether;
        uint256 poolIn = 10 ether;
        (ConstantProduct.Data memory data, GPv2Order.Data memory order) = setUpOrderWithReserves(poolIn, poolOut);

        uint256 amountOut = 100 ether;
        uint256 amountIn = getExpectedAmountIn([poolIn, poolOut], amountOut);
        (order.sellToken, order.buyToken) = (order.buyToken, order.sellToken);
        order.sellAmount = amountOut;
        order.buyAmount = amountIn - 1;

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "received amount too low"));
        verifyWrapper(orderOwner, data, order);
    }
}
