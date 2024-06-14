// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "lib/composable-cow/src/BaseConditionalOrder.sol";
import {ConstantProduct} from "./ConstantProduct.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

contract ConstantProductHelper is IPriceOracle {
    bytes32 public constant NUMERATOR_SLOT = keccak256("ConstantProductHelper.numerator");
    bytes32 public constant DENOMINATOR_SLOT = keccak256("ConstantProductHelper.denominator");

    function events() external view returns (bytes32 createPool, bytes32 enablePool, bytes32 disablePool) {
        return (
            bytes32(keccak256("Deployed(address,address,address,address)")),
            bytes32(keccak256("TradingEnabled(bytes32,(uint256,address,bytes,bytes32))")),
            bytes32(keccak256("TradingDisabled()"))
        );
    }

    /**
     * CoW AMM Pool helpers MUST return all tokens that may be traded on this pool
     */
    function tokens(ConstantProduct pool) external view returns (IERC20[] memory) {
        return [pool.token0(), pool.token1()];
    }

    /**
     * CoW AMM Pool helpers MUST provide a method for returning the canonical order
     * required to satisfy the pool's invariants, given a pricing vector, and
     * arbitrary data.
     * @param pool to calculate the order / signature for
     * @param numerator of the price vector
     * @param denominator of the price vector
     * @param data of arbitrary nature that may have been returned from
     * the 2nd argument to the pool enabling event. If arbitrary data isn't
     * supplied, supply `hex''`
     * @returns The GPv2Order.Data struct for the CoW Protocol JIT order and
     * it's associated ERC-1271 signature.
     */
    function getOrder(ConstantProduct pool, uint256 numerator, uint256 denominator, bytes calldata data)
        external
        view
        returns (GPv2Order.Data memory, bytes memory)
    {
        assembly ("memory-safe") {
            // Store the numerator and denominator in the slot
            tstore(NUMERATOR_SLOT, numerator)
            tstore(DENOMINATOR_SLOT, denominator)
        }

        ConstantProduct.TradingParams memory params = abi.decode(data, (ConstantProduct.TradingParams));
        ConstantProduct.TradingParams memory spoof = ConstantProduct.TradingParams({
            minTradedToken0: 0,
            priceOracle: address(this),
            priceOracleData: hex"",
            appData: params.appData
        });

        GPv2Order.Data memory order = pool.getOrder(spoof);
        return (order, abi.encode(order, params));
    }

    function getPrice(address, address, bytes calldata)
        external
        view
        returns (uint256 priceNumerator, uint256 priceDenominator)
    {
        assembly ("memory-safe") {
            priceNumerator := tload(NUMERATOR_SLOT)
            priceDenominator := tload(DENOMINATOR_SLOT)
        }
    }
}
