// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title CoW AMM Price Oracle Interface
 * @author CoW Protocol Developers
 * @dev A contract that can be used by the CoW AMM as as a price oracle.
 * The price source depends on the actual implementation; it could rely for
 * example on Uniswap, Balancer, Chainlink...
 */
interface IPriceOracle {
    /**
     * @dev Calling this function returns the price of token0 in terms of token1
     * as a fraction (numerator, denominator).
     * @param token0 The first token, whose price is determined based on the
     * second token.
     * @param token1 The second token; the price of the first token is
     * determined relative to this token.
     * @param data Any additional data that may be required by the specific
     * oracle implementation. For example, it could be a specific pool id for
     * balancer, or the address of a specific price feed for Chainlink.
     * @return priceNumerator The numerator of the price, expressed in amount of
     * token0 per amount of token1.
     * @return priceDenominator The denominator of the price, expressed in
     * amount of token0 per amount of token1.
     */
    function getPrice(address token0, address token1, bytes calldata data)
        external
        view
        returns (uint256 priceNumerator, uint256 priceDenominator);
}
