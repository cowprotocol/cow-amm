// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "lib/composable-cow/lib/@openzeppelin/contracts/interfaces/IERC20.sol";
import {ConditionalOrdersUtilsLib as Utils} from "lib/composable-cow/src/types/ConditionalOrdersUtilsLib.sol";
import {BaseConditionalOrder, IConditionalOrderGenerator, IConditionalOrder} from "lib/composable-cow/src/BaseConditionalOrder.sol";
import {GPv2Order} from "lib/composable-cow/lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import {IUniswapV2Pair} from "lib/uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract ConstantProduct is BaseConditionalOrder {
    uint256 internal constant MAX_BPS = 10_000;

    struct Data {
        IERC20 tokenA;
        IERC20 tokenB;
        address target;
        IUniswapV2Pair referencePair;
        uint256 minTradeVolumeBps;
        bytes32 appData;
    }

    /**
     * @inheritdoc IConditionalOrderGenerator
     */
    function getTradeableOrder(address owner, address, bytes32, bytes calldata staticInput, bytes calldata)
        public
        view
        override
        returns (GPv2Order.Data memory order)
    {
        ConstantProduct.Data memory data = abi.decode(staticInput, (Data));

        (uint256 my0, uint256 my1) = (data.tokenA.balanceOf(owner), data.tokenB.balanceOf(owner));
        uint256 myK = my0 * my1;

        (uint256 reserve0, uint256 reserve1) = (0, 0);
        if (data.referencePair.token0() == address(data.tokenA) && data.referencePair.token1() == address(data.tokenB))
        {
            (reserve0, reserve1,) = data.referencePair.getReserves();
        } else if (
            data.referencePair.token0() == address(data.tokenB) && data.referencePair.token1() == address(data.tokenA)
        ) {
            (reserve1, reserve0,) = data.referencePair.getReserves();
        } else {
            revert("invalid pair");
        }

        uint256 new1 = sqrt(myK * reserve1 / reserve0);
        uint256 new0 = myK / new1;

        order = GPv2Order.Data(
            IERC20(address(0)),
            IERC20(address(0)),
            address(0),
            0,
            0,
            Utils.validToBucket(3600),
            data.appData,
            0,
            GPv2Order.KIND_SELL,
            true,
            GPv2Order.BALANCE_ERC20,
            GPv2Order.BALANCE_ERC20
        );

        uint256 sellBalance = 0;
        if (new1 > my1) {
            sellBalance = my0;
            order.sellToken = data.tokenA;
            order.buyToken = data.tokenB;
            order.sellAmount = my0 - new0 - 1;
            order.buyAmount = new1 - my1 + 1;
        } else {
            sellBalance = my1;
            order.sellToken = data.tokenB;
            order.buyToken = data.tokenA;
            order.sellAmount = my1 - new1 - 1;
            order.buyAmount = new0 - my0 + 1;
        }

        if (order.sellAmount < sellBalance * data.minTradeVolumeBps / MAX_BPS) {
            revert IConditionalOrder.OrderNotValid("min amount");
        }
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
