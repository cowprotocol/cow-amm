// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IUniswapV2Pair} from "lib/uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

/**
 * @title CoW AMM UniswapV2 Price Oracle
 * @author CoW Protocol Developers
 * @dev This contract creates an oracle that is compatible with the IPriceOracle
 * interface and can be used by a CoW AMM to determine the current price of the
 * traded tokens on specific Uniswap v2 pools.
 */
contract UniswapV2PriceOracle is IPriceOracle {
    /**
     * Data required by the oracle to determine the current price.
     */
    struct Data {
        /**
         * The Uniswap v2 pair to use as a price reference.
         * It is expected that the pair's token0 and token1 coincide with the
         * tokens traded by the AMM and have the same order.
         */
        IUniswapV2Pair referencePair;
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
        require(token0 == oracleData.referencePair.token0(), "oracle: invalid token0");
        require(token1 == oracleData.referencePair.token1(), "oracle: invalid token1");
        (priceNumerator, priceDenominator,) = oracleData.referencePair.getReserves();
    }
}
