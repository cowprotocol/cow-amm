// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ComposableCoW} from "lib/composable-cow/src/ComposableCoW.sol";
import {GPv2Settlement} from "lib/composable-cow/lib/cowprotocol/src/contracts/GPv2Settlement.sol";
import {GPv2VaultRelayer} from "lib/composable-cow/lib/cowprotocol/src/contracts/GPv2VaultRelayer.sol";
import {Safe, FallbackManager, Enum} from "lib/composable-cow/lib/safe/contracts/Safe.sol";
import {
    ExtensibleFallbackHandler,
    SignatureVerifierMuxer
} from "lib/composable-cow/lib/safe/contracts/handler/ExtensibleFallbackHandler.sol";
import {IConditionalOrder} from "lib/composable-cow/src/BaseConditionalOrder.sol";

import {SafeModuleSafeERC20} from "./libraries/SafeModuleSafeERC20.sol";
import {SafeModuleAddress} from "./libraries/SafeModuleAddress.sol";
import {ConstantProduct, IPriceOracle, IERC20} from "./ConstantProduct.sol";

/**
 * @title CoW AMM Module
 * @author CoW Protocol Developers
 * @dev A Safe module for smoothing the experience when administering CoW AMMs.
 */
contract CowAmmModule {
    using SafeModuleSafeERC20 for Safe;
    using SafeModuleAddress for Safe;

    // --- immutable state

    /**
     * @notice The settlement contract for CoW Protocol on this network. This is only used by the
     * factory to determine the CowAmmModule is the correct implementation.
     */
    GPv2Settlement public immutable SETTLER;
    /**
     * @notice The EIP-712 signing domain separator for CoW Protocol on this network.
     */
    bytes32 public immutable COW_DOMAIN_SEPARATOR;
    /**
     * @notice The vault relayer that should be automatically approved for the tokens.
     */
    GPv2VaultRelayer public immutable VAULT_RELAYER;
    /**
     * @notice The address for the `ExtensibleFallbackHandler` on this network. This will be set as the
     * fallback handler on the Safe when the module is attached to a Safe.
     */
    ExtensibleFallbackHandler public immutable EXTENSIBLE_FALLBACK_HANDLER;
    /**
     * @notice The address for `ComposableCoW` on this network. This will be set as the
     * domain verifier in the `ExtensibleFallbackHandler` when the module is attached to a Safe.
     */
    ComposableCoW public immutable COMPOSABLE_COW;
    /**
     * @notice The address of the ConstantProduct programmatic order handler implementation of CoW AMMs.
     */
    IConditionalOrder public immutable HANDLER;
    /**
     * @notice The first of the two tokens traded by the AMM deployed by this module.
     */
    IERC20 public immutable token0;
    /**
     * @notice The second of the two tokens traded by the AMM deployed by this module.
     */
    IERC20 public immutable token1;

    // --- mutable state

    /**
     * @notice The active CoW AMM conditional order hash (bytes32(0) if none is active).
     */
    mapping(Safe => bytes32) public activeOrders;

    // --- constants

    /**
     * @dev The storage slot of the fallback handler on the safe
     * This is taken from the `FallbackManager` of Safe contracts. The reference can be found at:
     * https://github.com/safe-global/safe-smart-account/blob/767ef36bba88bdbc0c9fe3708a4290cabef4c376/contracts/base/FallbackManager.sol#L12
     */
    bytes32 internal constant _FALLBACK_HANDLER_STORAGE_SLOT =
        0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;
    /**
     * @dev The hash assigned to `activeOrders` when there is no active CoW AMM for a Safe.
     */
    bytes32 internal constant EMPTY_AMM_HASH = bytes32(0);

    // --- errors

    error ActiveAMM();
    error NoActiveAMM();
    error TokenBalanceZero();
    error NoActiveOrderToReplace();

    // --- events

    /**
     * @notice Emitted when a new CoW AMM is created.
     * @param safe The address of the Safe that created the AMM.
     * @param token0 The address of the first token in the pair.
     * @param token1 The address of the second token in the pair.
     * @param orderHash The hash of the conditional order that created the AMM.
     */
    event CowAmmCreated(Safe indexed safe, IERC20 indexed token0, IERC20 indexed token1, bytes32 orderHash);

    /**
     * @notice Emitted when an active CoW AMM is closed.
     * @param safe The address of the Safe that closed the AMM.
     * @param orderHash The hash of the conditional order that created the AMM.
     */
    event CowAmmClosed(Safe indexed safe, bytes32 orderHash);

    /**
     * @param _settler The address of the GPv2Settlement contract.
     * @param _extensibleFallbackHandler The address of the `ExtensibleFallbackHandler`.
     * @param _composableCow The address of `ComposableCoW`.
     * @param _handler The address of the ConstantProduct AMM implementation for creating new CoW AMMs.
     */
    constructor(
        GPv2Settlement _settler,
        ExtensibleFallbackHandler _extensibleFallbackHandler,
        ComposableCoW _composableCow,
        IConditionalOrder _handler,
        IERC20 _token0,
        IERC20 _token1
    ) {
        // GPv2 specifics to make sure we set the right things and they're immutable!
        SETTLER = GPv2Settlement(payable(_settler));
        COW_DOMAIN_SEPARATOR = SETTLER.domainSeparator();
        VAULT_RELAYER = SETTLER.vaultRelayer();

        // ComposableCoW specifics
        EXTENSIBLE_FALLBACK_HANDLER = _extensibleFallbackHandler;
        COMPOSABLE_COW = _composableCow;
        HANDLER = _handler;

        token0 = _token0;
        token1 = _token1;
    }

    /**
     * @notice Creates a new CoW AMM with the given parameters.
     * @param minTradedToken0 The minimum amount of token0 before the AMM attempts auto-rebalance.
     * @param priceOracle The address of the price oracle to use for the AMM.
     * @param priceOracleData The data to pass to the price oracle.
     * @param appData The app data to pass to the AMM.
     * @return The hash of the conditional order that created the AMM.
     */
    function createAmm(uint256 minTradedToken0, address priceOracle, bytes calldata priceOracleData, bytes32 appData)
        external
        returns (bytes32)
    {
        // Assume the caller is a Safe
        Safe safe = Safe(payable(msg.sender));

        if (activeOrders[safe] != EMPTY_AMM_HASH) {
            // If there is an active order, the user must close it before creating a new one
            // This is not fool-proof as the user could create another AMM outside of this module
            revert ActiveAMM();
        }

        return _createAmm(safe, minTradedToken0, priceOracle, priceOracleData, appData);
    }

    /**
     * @notice Replaces the active CoW AMM that was created with this module with a new one.
     * @param minTradedToken0 The minimum amount of token0 before the AMM attempts auto-rebalance.
     * @param priceOracle The address of the price oracle to use for the AMM.
     * @param priceOracleData The data to pass to the price oracle.
     * @param appData The app data to pass to the AMM.
     * @return The hash of the conditional order that created the new AMM.
     * @dev This function internally just calls `closeAmm` and then `createAmm`.
     */
    function replaceAmm(uint256 minTradedToken0, address priceOracle, bytes calldata priceOracleData, bytes32 appData)
        external
        returns (bytes32)
    {
        // Assume the caller is a Safe
        Safe safe = Safe(payable(msg.sender));

        bytes32 _activeOrder = activeOrders[safe];
        if (_activeOrder == EMPTY_AMM_HASH) {
            revert NoActiveOrderToReplace();
        } else {
            _closeAmm(safe, _activeOrder);
        }
        return _createAmm(safe, minTradedToken0, priceOracle, priceOracleData, appData);
    }

    /**
     * @notice Closes the active CoW AMM.
     * @dev This function will call `ComposableCoW.remove` with the active order if there is one.
     */
    function closeAmm() external {
        Safe safe = Safe(payable(msg.sender));
        bytes32 _activeOrder = activeOrders[safe];
        if (_activeOrder != EMPTY_AMM_HASH) {
            _closeAmm(safe, _activeOrder);
        }
    }

    // --- Internal functions

    /**
     * @notice Creates a new CoW AMM with the given parameters.
     * @param safe The address of the Safe that owns the new CoW AMM.
     * @param minTradedToken0 The minimum amount of token0 before the AMM attempts auto-rebalance.
     * @param priceOracle The address of the price oracle to use for the AMM.
     * @param priceOracleData The data to pass to the price oracle.
     * @param appData The app data to pass to the AMM.
     * @return orderHash The hash of the conditional order that created the AMM.
     */
    function _createAmm(
        Safe safe,
        uint256 minTradedToken0,
        address priceOracle,
        bytes calldata priceOracleData,
        bytes32 appData
    ) internal returns (bytes32 orderHash) {
        // Always make sure the module is setup before doing anything
        _setup(safe);

        // We can't create a new CoW AMM if there isn't anything to trade!
        if (token0.balanceOf(address(safe)) == 0 || token1.balanceOf(address(safe)) == 0) {
            revert TokenBalanceZero();
        }

        // Set the token allowances for the vault relayer
        _setAllowance(safe, token0);
        _setAllowance(safe, token1);

        // Prepare the data for the new CoW AMM
        ConstantProduct.Data memory data = ConstantProduct.Data({
            minTradedToken0: minTradedToken0,
            priceOracle: IPriceOracle(priceOracle),
            priceOracleData: priceOracleData,
            appData: appData
        });

        // Wrap the data in a conditional order
        IConditionalOrder.ConditionalOrderParams memory params = IConditionalOrder.ConditionalOrderParams({
            handler: HANDLER,
            salt: keccak256(abi.encodePacked(block.timestamp)),
            staticInput: abi.encode(data)
        });

        // Create the new CoW AMM
        safe.functionCall(address(COMPOSABLE_COW), abi.encodeCall(ComposableCoW.create, (params, true)));

        // Set the new CoW AMM as the active order
        // Would be nice if the `ComposableCoW.create` returned the hash as it's
        // already calculated there and would prevent double-hashing and save some gas!
        orderHash = COMPOSABLE_COW.hash(params);
        activeOrders[safe] = orderHash;

        emit CowAmmCreated(safe, token0, token1, orderHash);
    }

    /**
     * @notice Closes the active CoW AMM, without checking if there is an active order.
     * @dev This is for gas savings when the caller already knows there is an active order.
     * @param safe The address of the Safe that owns the active CoW AMM.
     * @param orderHash The hash of the conditional order that created the AMM.
     */
    function _closeAmm(Safe safe, bytes32 orderHash) internal {
        safe.functionCall(address(COMPOSABLE_COW), abi.encodeCall(ComposableCoW.remove, (orderHash)));
        emit CowAmmClosed(safe, orderHash);
        activeOrders[safe] = EMPTY_AMM_HASH;
    }

    /**
     * @notice Conducts internal Safe setup to ensure that the creation of CoW AMMs is smooth.
     */
    function _setup(Safe safe) internal {
        address fallbackHandler = abi.decode(safe.getStorageAt(uint256(_FALLBACK_HANDLER_STORAGE_SLOT), 1), (address));
        if (fallbackHandler != address(EXTENSIBLE_FALLBACK_HANDLER)) {
            safe.functionCall(
                address(safe),
                abi.encodeCall(FallbackManager.setFallbackHandler, (address(EXTENSIBLE_FALLBACK_HANDLER)))
            );
        }

        address domainVerifier = address(EXTENSIBLE_FALLBACK_HANDLER.domainVerifiers(safe, COW_DOMAIN_SEPARATOR));
        if (domainVerifier != address(COMPOSABLE_COW)) {
            safe.functionCall(
                address(safe),
                abi.encodeCall(SignatureVerifierMuxer.setDomainVerifier, (COW_DOMAIN_SEPARATOR, COMPOSABLE_COW))
            );
        }
    }

    /**
     * @notice A helper function for setting ERC20 token allowances on the Safe
     */
    function _setAllowance(Safe safe, IERC20 token) internal {
        if (token.allowance(address(safe), address(VAULT_RELAYER)) < type(uint256).max) {
            safe.forceApprove(token, address(VAULT_RELAYER), type(uint256).max);
        }
    }
}
