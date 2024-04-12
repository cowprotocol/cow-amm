// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

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
    address public immutable settler;

    /**
     * @param _settler The address of the GPv2Settlement contract.
     */
    constructor(address _settler) {
        settler = _settler;
    }
}
