// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title CoW Protocol Settlement Interface
 * @author CoW Protocol Developers
 * @dev This interface collects the functions of the CoW Protocol settlement
 * contract that are used by the CoW AMM.
 */
interface ISettlement {
    /**
     * @dev The domain separator used for signing orders that gets mixed in
     * making signatures for different domains incompatible. This domain
     * separator is computed following the EIP-712 standard and has replay
     * protection mixed in so that signed orders are only valid for specific
     * GPv2 contracts.
     */
    function domainSeparator() external returns (bytes32);

    /**
     * @dev The address of the vault relayer: the contract that handles
     * withdrawing tokens from the user to the settlement contract. A user who
     * wants to sell a token on CoW Swap must approve this contract to spend the
     * token.
     */
    function vaultRelayer() external returns (address);
}
