// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IWatchtowerCustomErrors} from "../interfaces/IWatchtowerCustomErrors.sol";
/**
 * @title Chainlink Price Oracle
 * @author GUNBOATs
 * @dev This contract creates an oracle that is compatible with the IPriceOracle
 * interface and can be used by a CoW AMM to determine the current price of the
 * traded tokens from Chainlink Data Feeds with decimals lower or equal to 18.
 */

contract ChainlinkPriceOracle is IPriceOracle, IWatchtowerCustomErrors {
    /**
     * @param token0Feed Address of token0 oracle
     * @param token1Feed Address of token1 oracle
     * @param timeThreshold Amount of seconds before the oracle is considered stale
     * @param backoff Duration to indicate how long the watchtower should wait for the oracle to refresh
     */
    struct Data {
        address token0Feed;
        address token1Feed;
        uint256 timeThreshold;
        uint256 backoff;
    }
    /**
     * @dev There is no mapping between Chainlink oracle and the token address,
     * so the user must check that the oracle corresponds to the token themselves.
     * @inheritdoc IPriceOracle
     */

    function getPrice(address, address, bytes calldata data)
        external
        view
        returns (uint256 priceNumerator, uint256 priceDenominator)
    {
        Data memory OracleData = abi.decode(data, (Data));
        AggregatorV3Interface token0Feed = AggregatorV3Interface(OracleData.token0Feed);
        AggregatorV3Interface token1Feed = AggregatorV3Interface(OracleData.token1Feed);
        (
            /* uint80 roundId*/
            ,
            int256 token0Answer,
            /* uint256 startedAt */
            ,
            uint256 token0Timestamp,
            /* uint80 answerInRound */
        ) = token0Feed.latestRoundData();
        (
            /* uint80 roundId*/
            ,
            int256 token1Answer,
            /* uint256 startedAt */
            ,
            uint256 token1Timestamp,
            /* uint80 answerInRound */
        ) = token1Feed.latestRoundData();
        uint256 timestamp = block.timestamp;
        if (
            timestamp - token0Timestamp >= OracleData.timeThreshold
                || timestamp - token1Timestamp >= OracleData.timeThreshold
        ) {
            revert PollTryAtEpoch(block.timestamp + OracleData.backoff, "stale oracle");
        }
        uint256 token0Decimals = token0Feed.decimals();
        uint256 token1Decimals = token1Feed.decimals();
        if (token0Decimals == token1Decimals) {
            priceNumerator = uint256(token1Answer);
            priceDenominator = uint256(token0Answer);
        } else {
            /**
             * While most oracles in Chainlink use 8 decimals for USD pair and 18 for ETH pair,
             * AMPL/USD has 18 decimals so in the rare case we will have to normalize it.
             * Oracles with more than 18 decimals exist, since as Synthetix Debt Shares,
             * but they cannot be traded and thus are not in scope of this contract.
             */
            priceNumerator = uint256(token1Answer) * (10 ** (18 - token1Decimals));
            priceDenominator = uint256(token0Answer) * (10 ** (18 - token0Decimals));
        }
    }
}
