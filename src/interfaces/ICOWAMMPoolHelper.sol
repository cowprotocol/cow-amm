// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.24;

import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {GPv2Interaction} from "cowprotocol/contracts/libraries/GPv2Interaction.sol";

/**
 * @notice Pool-specific helper interface for AMM's operating in CoW Protocol.
 */
interface ICOWAMMPoolHelper {
    /**
     * All functions that take `pool` as an argument MUST revert with this error
     * if the `pool` does not exist.
     * @dev Indexers monitoring CoW AMM pools MAY use this as a signal to purge the
     *      pool from their index.
     */
    error PoolDoesNotExist();
    /**
     * All functions that take `pool` as an argument MUST revert with this error
     * in the event that the pool is paused (ONLY applicable if the pool is pausable).
     * @dev Indexers monitoring CoW AMM pools SHOULD use this as a signal to retain
     *      the pool in the index with back-off on polling for orders.
     */
    error PoolIsPaused();
    /**
     * All functions that take `pool` as an argument MUST revert with this error
     * in the event that the pool is closed (ONLY applicable if the pool can be
     * closed).
     * @dev Indexers monitoring CoW AMM pools MAY use this as a signal to purge the
     *      pool from their index.
     */
    error PoolIsClosed();
    /**
     * Returned by the `order` function if there is no order matching the supplied
     * parameters.
     */
    error NoOrder();

    /**
     * AMM Pool helpers MUST return the factory target for indexing of CoW AMM pools.
     */
    function factory() external view returns (address);
    /**
     * AMM Pool helpers MUST return all tokens that may be traded on this pool.
     * The order of the tokens is expected to be consistent and must be the same
     * as that used for the input price vector in the `order` function.
     */
    function tokens(address pool) external view returns (address[] memory);
    /**
     * AMM Pool helpers MUST provide a method for returning the canonical order
     * required to satisfy the pool's invariants, given a pricing vector.
     * @dev Reverts with `NoOrder` if the `pool` has no canonical order matching the
     *      given price vector.
     * @param pool to calculate the order / signature for
     * @param prices supplied for determining the order, assumed to be in the
     *        same order as returned from `tokens(pool)`.
     * @return order The CoW Protocol JIT order
     * @return preInteractions The array array for any **PRE** interactions (empty if none)
     * @return postInteractions The array array for any **POST** interactions (empty if none)
     * @return sig The ERC-1271 signature for the order
     */
    function order(address pool, uint256[] calldata prices)
        external
        view
        returns (GPv2Order.Data memory order, GPv2Interaction.Data[] memory preInteractions, GPv2Interaction.Data[] memory postInteractions, bytes memory sig);
}
