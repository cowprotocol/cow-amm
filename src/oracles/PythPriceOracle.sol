// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Math} from "lib/openzeppelin/contracts/utils/math/Math.sol";
import {stdMath} from "lib/openzeppelin/lib/forge-std/src/StdMath.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IConditionalOrder} from "lib/composable-cow/src/interfaces/IConditionalOrder.sol";
import {IWatchtowerCustomErrors} from "../interfaces/IWatchtowerCustomErrors.sol";
import {IPyth, PythStructs} from "../interfaces/IPyth.sol";

/**
 * @title Pyth Price Oracle
 * @author yvesfracari
 * @dev This contract creates an oracle that is compatible with the IPriceOracle
 * interface and can be used by a CoW AMM to determine the current price of the
 * traded tokens from Pyth Data Feeds with decimals lower or equal to 18.
 */
contract PythPriceOracle is IPriceOracle, IWatchtowerCustomErrors {
    /**
     * @notice The Pyth entrypoint on the network
     */
    IPyth public pythAggregator;
    uint256 private constant _MAX_BPS = 10000;

    /**
     * @param token0Feed Id of token0 price feed
     * @param token1Feed Id of token1 price feed
     * @param minPrecisionBps Minimum precision considering (price-error)/price in bases points
     * @param timeThreshold Amount of seconds before the oracle is considered stale
     * @param backoff Duration to indicate how long the watchtower should wait for the oracle to refresh
     */
    struct Data {
        bytes32 token0Feed;
        bytes32 token1Feed;
        uint256 minPrecisionBps;
        uint256 timeThreshold;
        uint256 backoff;
    }

    /**
     * @param _pythAggregator The address of the Pyth aggregator in the current chain.
     */
    constructor(IPyth _pythAggregator) {
        pythAggregator = _pythAggregator;
    }

    /**
     * @dev There is no mapping between Pyth oracle and the token address,
     * so the user must check that the oracle corresponds to the token themselves.
     * @inheritdoc IPriceOracle
     */
    function getPrice(address, address, bytes calldata data)
        external
        view
        returns (uint256 priceNumerator, uint256 priceDenominator)
    {
        Data memory oracleData = abi.decode(data, (Data));

        PythStructs.Price memory price0 = pythAggregator.getPriceUnsafe(oracleData.token0Feed);
        PythStructs.Price memory price1 = pythAggregator.getPriceUnsafe(oracleData.token1Feed);

        uint256 minPublishTime = block.timestamp - oracleData.timeThreshold;

        if (price0.price < 0 || price1.price < 0) {
            revert IConditionalOrder.OrderNotValid("negative price");
        }

        if (price0.expo > 0 || price1.expo > 0 || price0.expo < -18 || price1.expo < -18) {
            revert IConditionalOrder.OrderNotValid("unsupported decimals");
        }

        if (minPublishTime > price0.publishTime || minPublishTime > price1.publishTime) {
            revert PollTryAtEpoch(block.timestamp + oracleData.backoff, "stale oracle");
        }

        uint256 price0Uint256 = stdMath.abs(int256(price0.price));
        uint256 price1Uint256 = stdMath.abs(int256(price1.price));

        uint256 price0PrecisionBps = Math.mulDiv(price0Uint256 - uint256(price0.conf), _MAX_BPS, price0Uint256);
        uint256 price1PrecisionBps = Math.mulDiv(price1Uint256 - uint256(price1.conf), _MAX_BPS, price1Uint256);
        if (price0PrecisionBps < oracleData.minPrecisionBps || price1PrecisionBps < oracleData.minPrecisionBps) {
            revert PollTryAtEpoch(block.timestamp + oracleData.backoff, "imprecise oracle");
        }

        if (price0.expo == price1.expo) {
            priceNumerator = price1Uint256;
            priceDenominator = price0Uint256;
        } else {
            priceNumerator = price1Uint256 * (10 ** (18 - stdMath.abs(int256(price1.expo))));
            priceDenominator = price0Uint256 * (10 ** (18 - stdMath.abs(int256(price0.expo))));
        }
    }
}
