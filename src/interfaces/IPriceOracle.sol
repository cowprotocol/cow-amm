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
     * @dev Calling this function returns the price of token1 in terms of token0
     * as a fraction (numerator, denominator).
     * For example, in a pool where token0 is DAI, token1 is ETH, and ETH is
     * worth 2000 DAI, valid output tuples would be (2000, 1), (20000, 10), ...
     * @param token0 The first token, whose price is determined based on the
     * second token.
     * @param token1 The second token; the price of the first token is
     * determined relative to this token.
     * @param data Any additional data that may be required by the specific
     * oracle implementation. For example, it could be a specific pool id for
     * balancer, or the address of a specific price feed for Chainlink.
     * We recommend this data be implemented as the abi-encoding of a dedicated
     * data struct for ease of type-checking and decoding the input. 
     * @return priceNumerator The numerator of the price, expressed in amount of
     * token1 per amount of token0.
     * @return priceDenominator The denominator of the price, expressed in
     * amount of token1 per amount of token0.
     */
    function getPrice(address token0, address token1, bytes calldata data)
        external
        view
        returns (uint256 priceNumerator, uint256 priceDenominator);
}
