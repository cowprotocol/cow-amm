// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/**
 * @title Helper factory interface for back-end readability of deployed AMMs
 * @author CoW Protocol Developers
 */
interface ICOWAMMPoolFactory {
    /**
     * AMM protocols capable of operating as a CoW AMM MUST emit an event on pool
     * creation.
     * @param amm The address of the newly tradeable CoW AMM Pool
     */
    event COWAMMPoolCreated(address amm);
}
