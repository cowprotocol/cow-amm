// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IConditionalOrder} from "lib/composable-cow/src/BaseConditionalOrder.sol";
import {IERC20} from "lib/composable-cow/lib/@openzeppelin/contracts/interfaces/IERC20.sol";
import {Math} from "lib/openzeppelin/contracts/utils/math/Math.sol";

import {IVault, IWeightedPool} from "../interfaces/IBalancer.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/**
 * @title CoW AMM Balancer Weighted Price Oracle
 * @author CoW Protocol Developers
 * @dev This contract creates an oracle that is compatible with the IPriceOracle
 * interface and can be used by a CoW AMM to determine the current price of the
 * traded tokens on specific Balancer weighted pools.
 * No other Balancer pool type is supported.
 */
contract BalancerWeightedPoolPriceOracle is IPriceOracle {
    /**
     * Address of the Balancer vault.
     */
    IVault public vault;

    /**
     * Data required by the oracle to determine the current price.
     */
    struct Data {
        /**
         * The Balancer poolId that references an instance of a weighted pool.
         * Note that the contract doesn't verify that the pool is indeed a
         * weighted pool. If the id refers to another type of pool, then the
         * oracle may return an incorrect price.
         */
        bytes32 poolId;
    }

    /**
     * How many significant bits should be preserved from truncation.
     */
    uint256 public constant TOLERANCE = 14;

    /**
     * @param vault_ The address of the Balancer vault in the current chain.
     */
    constructor(IVault vault_) {
        vault = vault_;
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function getPrice(address token0, address token1, bytes calldata data) external view returns (uint256, uint256) {
        IWeightedPool pool;
        IERC20[] memory tokens;
        uint256[] memory balances;
        uint256[] memory weights;
        {
            // Note: function calls in this scope aren't affected by the paused
            // state
            bytes32 poolId = abi.decode(data, (Data)).poolId;
            // If the pool isn't registered, then the next call reverts
            try vault.getPool(poolId) returns (address a, IVault.PoolSpecialization) {
                pool = IWeightedPool(a);
            } catch (bytes memory) {
                revert IConditionalOrder.OrderNotValid("invalid pool id");
            }

            (tokens, balances,) = vault.getPoolTokens(poolId);

            // Unfortunately, this function is available also for pools that
            // aren't weighted pools
            try pool.getNormalizedWeights() returns (uint256[] memory weights_) {
                weights = weights_;
            } catch (bytes memory) {
                revert IConditionalOrder.OrderNotValid("not a weighted pool");
            }
        }

        uint256 weightToken0 = 0;
        uint256 weightToken1 = 0;
        uint256 balanceToken0;
        uint256 balanceToken1;
        for (uint256 i; i < tokens.length;) {
            address token;
            unchecked {
                token = address(tokens[i]);
            }
            if (token == token0) {
                weightToken0 = weights[i];
                balanceToken0 = balances[i];
            } else if (token == token1) {
                weightToken1 = weights[i];
                balanceToken1 = balances[i];
            }
            unchecked {
                i++;
            }
        }

        if (weightToken0 == 0) {
            revert IConditionalOrder.OrderNotValid("pool does not trade token0");
        }
        if (weightToken1 == 0) {
            revert IConditionalOrder.OrderNotValid("pool does not trade token1");
        }

        // https://docs.balancer.fi/reference/math/weighted-math.html#spot-price
        uint256 priceNumerator = balanceToken0 * weightToken1;
        uint256 priceDenominator = balanceToken1 * weightToken0;

        // Numerator and denominator are very likely to be large. We limit the
        // bit size of the output as recommended in the IPriceOracle interface
        // so that this price oracle doesn't cause unexpected overflow reverts
        // when used by `getTradeableOrder`.
        return reduceOutputBytes(priceNumerator, priceDenominator);
    }

    /**
     * @dev The two input values are truncated off their least significant bits
     * by the same number of bits while trying to make them fit 128 bits.
     * The number of bits that is truncated is always the same for both values.
     * If truncating meant that less significant bits than `TOLERANCE` remained,
     * then this function truncates less to preserve `TOLERANCE` bits in the
     * smallest value, even if one of the output values ends up having more than
     * 128 bits of size.
     * @param num1 First input value.
     * @param num2 Second input value.
     * @return The two original input values in the original order with some of
     * the least significant bits truncated.
     */
    function reduceOutputBytes(uint256 num1, uint256 num2) internal pure returns (uint256, uint256) {
        uint256 max;
        uint256 min;
        if (num1 > num2) {
            (max, min) = (num1, num2);
        } else {
            (max, min) = (num2, num1);
        }
        uint256 logMax = Math.log2(max, Math.Rounding.Up);
        uint256 logMin = Math.log2(min, Math.Rounding.Down);

        if ((logMax <= 128) || (logMin <= TOLERANCE)) {
            return (num1, num2);
        }
        uint256 shift;
        unchecked {
            shift = logMax - 128;
            if (logMin < TOLERANCE + shift) {
                shift = logMin - TOLERANCE;
            }
        }
        return (num1 >> shift, num2 >> shift);
    }
}
