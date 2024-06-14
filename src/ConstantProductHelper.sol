// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.24;

import {IERC20, GPv2Order} from "lib/composable-cow/src/BaseConditionalOrder.sol";
import {ConstantProduct} from "./ConstantProduct.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

contract ConstantProductHelper is IPriceOracle {
    // uint256(keccak256("ConstantProductHelper.numerator")) - 1
    uint256 public constant NUMERATOR_SLOT = 0x223dcd62dbf383e930e6aa5d74a39264cb580dbc29ee32ecbfc9edd7179ff604;
    // uint256(keccak256("ConstantProductHelper.denominator")) - 1
    uint256 public constant DENOMINATOR_SLOT = 0x30843a766054dd7fc4b0ac76c32c0a5da91a64e646d782e95f94d37ff51d4178;

    function events() external pure returns (bytes32 createPool, bytes32 enablePool, bytes32 disablePool) {
        return (
            bytes32(keccak256("Deployed(address,address,address,address)")),
            bytes32(keccak256("TradingEnabled(bytes32,(uint256,address,bytes,bytes32))")),
            bytes32(keccak256("TradingDisabled()"))
        );
    }

    /**
     * CoW AMM Pool helpers MUST return all tokens that may be traded on this pool
     */
    function tokens(ConstantProduct pool) external view returns (IERC20[] memory tokens_) {
        tokens_ = new IERC20[](2);
        tokens_[0] = IERC20(pool.token0());
        tokens_[1] = IERC20(pool.token1());
        return tokens_;
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
     * @return The GPv2Order.Data struct for the CoW Protocol JIT order and
     * it's associated ERC-1271 signature.
     */
    function getOrder(ConstantProduct pool, uint256 numerator, uint256 denominator, bytes calldata data)
        external
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
            priceOracle: IPriceOracle(address(this)),
            priceOracleData: hex"",
            appData: params.appData
        });

        GPv2Order.Data memory order = pool.getTradeableOrder(spoof);
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
