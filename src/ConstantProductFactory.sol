// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IConditionalOrder} from "lib/composable-cow/src/ComposableCoW.sol";

import {ConstantProduct, ISettlement, GPv2Order} from "./ConstantProduct.sol";

/**
 * @title CoW AMM Factory
 * @author CoW Protocol Developers
 * @dev Factory contract for the CoW AMM, an automated market maker based on the
 * concept of function-maximising AMMs.
 * The factory deploys new AMM and is responsible for managing deposits,
 * enabling/disabling trading and updating trade parameters.
 */
contract ConstantProductFactory {
    /**
     * @notice The settlement contract for CoW Protocol on this network.
     */
    ISettlement public immutable settler;

    /**
     * @notice Sanity check to make sure that `getTradeableOrderWithSignature`
     * is being called with parameters that were supposed to be handled by this
     * factory.
     */
    error CanOnlyHandleOrdersForItself();
    /**
     * @notice Sanity check to make sure that `getTradeableOrderWithSignature`
     * is being called with parameters that are currently enabled for trading
     * on the AMM.
     *
     * @param computed the hash of the input parameters
     * @param ammHash the hash of the parameters that are allowed to be traded
     * on the AMM. If the hash is empty, then trading for this order has been
     * disabled and there is currently no open order available
     */
    error ParamsHashDoesNotMatchEnabledOrder(bytes32 computed, bytes32 ammHash);

    /**
     * @param _settler The address of the GPv2Settlement contract.
     */
    constructor(ISettlement _settler) {
        settler = _settler;
    }

    /**
     * @notice This function exists to let the watchtower off-chain service
     * automatically create AMM orders and post them on the orderbook. It
     * outputs an order for the input AMM together with a valid signature.
     * @dev Some parameters are unused as they refer to features of
     * ComposableCoW that aren't implemented in this contract. They are still
     * needed to let the watchtower interact with this contract in the same way
     * as ComposableCoW.
     * @param amm owner of the order.
     * @param params `ConditionalOrderParams` for the order; precisely, the
     * handler must be this contract, the salt can be any value, and the static
     * input must be the current trading parameters of the AMM.
     * @return order discrete order for submitting to CoW Protocol API
     * @return signature for submitting to CoW Protocol API
     */
    function getTradeableOrderWithSignature(
        ConstantProduct amm,
        IConditionalOrder.ConditionalOrderParams calldata params,
        bytes calldata, // offchainInput
        bytes32[] calldata // proof
    ) external view returns (GPv2Order.Data memory order, bytes memory signature) {
        if (address(params.handler) != address(this)) {
            revert CanOnlyHandleOrdersForItself();
        }

        ConstantProduct.TradingParams memory tradingParams =
            abi.decode(params.staticInput, (ConstantProduct.TradingParams));
        bytes32 inputHash = amm.hash(tradingParams);
        bytes32 ammHash = amm.tradingParamsHash();
        if (inputHash != ammHash) {
            revert ParamsHashDoesNotMatchEnabledOrder(inputHash, ammHash);
        }

        // Note: the salt in params is ignored.

        order = amm._getTradeableOrder(address(amm), tradingParams);
        signature = abi.encode(order, tradingParams);
    }
}
