// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {Math} from "lib/openzeppelin/contracts/utils/math/Math.sol";

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IUniswapV3Pool} from "../interfaces/IUniswapV3Pool.sol";

/**
 * @title CoW AMM UniswapV3 Price Oracle
 * @author yvesfracari
 * @dev This contract creates an oracle that is compatible with the IPriceOracle
 * interface and can be used by a CoW AMM to determine the current price of the
 * traded tokens on specific Uniswap v3 pools.
 */
contract UniswapV3PriceOracle is IPriceOracle {
    /**
     * Data required by the oracle to determine the current price.
     */
    struct Data {
        /**
         * The Uniswap v3 pool to use as a price reference.
         * It is expected that the pool's token0 and token1 coincide with the
         * tokens traded by the AMM and have the same order.
         */
        IUniswapV3Pool referencePool;
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getPrice(address token0, address token1, bytes calldata data)
        external
        view
        returns (uint256 priceNumerator, uint256 priceDenominator)
    {
        Data memory oracleData = abi.decode(data, (Data));
        (uint160 sqrtPriceX96,,,,,,) = oracleData.referencePool.slot0();
        IERC20 uniswapToken0 = IERC20(oracleData.referencePool.token0());
        IERC20 uniswapToken1 = IERC20(oracleData.referencePool.token1());
        uint8 token0Decimals = uniswapToken0.decimals();
        uint8 token1Decimals = uniswapToken1.decimals();

        // From UniswapV3 Docs: price=(sqrtPriceX96/2^96)ˆ2
        uint256 price = Math.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 4 ** 96);
        priceNumerator = Math.mulDiv(price, 10 ** token0Decimals, 1);
        priceDenominator = 10 ** token1Decimals;

        if (token0 == address(uniswapToken1)) {
            (priceNumerator, priceDenominator) = (priceDenominator, priceNumerator);
            (uniswapToken0, uniswapToken1) = (uniswapToken1, uniswapToken0);
        }
        require(token0 == address(uniswapToken0), "oracle: invalid token0");
        require(token1 == address(uniswapToken1), "oracle: invalid token1");
    }
}
