// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ComposableCoW} from "lib/composable-cow/src/ComposableCoW.sol";
import {GPv2Settlement} from "lib/composable-cow/lib/cowprotocol/src/contracts/GPv2Settlement.sol";
import {Safe, Enum} from "lib/composable-cow/lib/safe/contracts/Safe.sol";
import {ExtensibleFallbackHandler} from "lib/composable-cow/lib/safe/contracts/handler/ExtensibleFallbackHandler.sol";
import {ConstantProduct, IPriceOracle, IERC20} from "./ConstantProduct.sol";
import {IConditionalOrder} from "lib/composable-cow/src/BaseConditionalOrder.sol";

/**
 * @title CoW AMM Module Factory
 * @author CoW Protocol Developers
 * @dev A factory for creating CoW AMM modules.
 */
contract CowAmmModuleFactory {
    using Clones for address;

    /**
     * @notice The implementation of the CoW AMM module with the respective network-specific addresses and amm handler.
     */
    CowAmmModule public immutable IMPLEMENTATION;

    /**
     * @dev Error messages for the factory.
     */
    error InvalidParameter();

    /**
     * @notice Index all cow amm module factories created.
     * @param implementation The address of the CoW AMM module implementation.
     */
    event CowAmmModuleFactoryCreated(address indexed implementation);

    /**
     * @notice Index all cow amm modules created.
     * @param implementation The address of the CoW AMM module implementation.
     * @param safe The address of the safe that the module will be attached to.
     */
    event CowAmmModuleCreated(address indexed implementation, address indexed safe);

    /**
     * @param _implementation The address of the CoW AMM module implementation.
     * @param _settler The address of the GPv2Settlement contract.
     * @param _extensibleFallbackHandler The address of the `ExtensibleFallbackHandler`.
     * @param _composableCow The address of `ComposableCoW`.
     * @param _ammHandler The address of the AMM implementation (e.g. `ConstantProduct`) for creating new CoW AMMs.
     */
    constructor(
        CowAmmModule _implementation,
        address _settler,
        address _extensibleFallbackHandler,
        address _composableCow,
        address _ammHandler
    ) {
        // Make sure that the addresses within the implementation correspond correctly to the given addresses
        bool isSettler = address(_implementation.SETTLER()) == _settler;
        bool isExtensibleFallbackHandler =
            address(_implementation.EXTENSIBLE_FALLBACK_HANDLER()) == _extensibleFallbackHandler;
        bool isComposableCow = address(_implementation.COMPOSABLE_COW()) == _composableCow;
        bool isAmmHandler = address(_implementation.HANDLER()) == _ammHandler;
        if (!isSettler || !isExtensibleFallbackHandler || !isComposableCow || !isAmmHandler) {
            revert InvalidParameter();
        }

        // Set the implementation
        IMPLEMENTATION = _implementation;

        emit CowAmmModuleFactoryCreated(address(_implementation));
    }

    /**
     * @notice Creates a new CoW AMM module for the given safe.
     * @param safe The address of the safe that the module will be attached to.
     * @return The address of the new CoW AMM module.
     */
    function create(address safe) external returns (address) {
        CowAmmModule module = CowAmmModule(address(IMPLEMENTATION).cloneDeterministic(bytes20(safe)));
        module.initialize(safe);

        emit CowAmmModuleCreated(address(module), safe);

        return address(module);
    }

    /**
     * @notice Predicts the address of a new CoW AMM module for the given safe.
     * @param safe The address of the safe that the module will be attached to.
     * @return The address of the new CoW AMM module.
     */
    function predictAddress(address safe) external view returns (address) {
        return address(IMPLEMENTATION).predictDeterministicAddress(bytes20(safe), address(this));
    }
}

/**
 * @title CoW AMM Module
 * @author CoW Protocol Developers
 * @dev A Safe module for smoothing the experience when administering CoW AMMs.
 */
contract CowAmmModule {
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
    address public immutable VAULT_RELAYER;
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
     * @notice The address of the safe that this module is attached to.
     */
    Safe public safe;
    /**
     * @notice The active CoW AMM conditional order hash (bytes32(0) if none is active).
     */
    bytes32 public activeOrder;

    /**
     * @dev The address of this module implementation (for checking if in delegatecall).
     */
    address private immutable _ORIGINAL_ADDRESS;
    /**
     * @dev The storage slot of the fallback handler on the safe
     */
    bytes32 internal constant _FALLBACK_HANDLER_STORAGE_SLOT =
        0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;

    error NotAClone();
    error OnlySafe();
    error ModuleAlreadyInitialized();
    error NoActiveAMM();
    error TokenBalanceZero();

    /**
     * @notice Emitted when a new CoW AMM is created.
     * @param orderHash The hash of the conditional order that created the AMM.
     * @param token0 The address of the first token in the pair.
     * @param token1 The address of the second token in the pair.
     */
    event CowAmmCreated(bytes32 indexed orderHash, address indexed token0, address indexed token1);

    /**
     * @notice Emitted when an active CoW AMM is closed.
     */
    event CowAmmClosed(bytes32 indexed orderHash);

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
        IConditionalOrder _handler
    ) {
        // GPv2 specifics to make sure we set the right things and they're immutable!
        SETTLER = _settler;
        COW_DOMAIN_SEPARATOR = SETTLER.domainSeparator();
        VAULT_RELAYER = address(SETTLER.vaultRelayer());

        // ComposableCoW specifics
        EXTENSIBLE_FALLBACK_HANDLER = _extensibleFallbackHandler;
        COMPOSABLE_COW = _composableCow;
        HANDLER = _handler;

        // Remember who we are so we can check if we're in a delegatecall
        _ORIGINAL_ADDRESS = address(this);
    }

    modifier onlySafe() {
        if (msg.sender != address(safe)) {
            revert OnlySafe();
        }
        _;
    }

    /**
     * @notice Initializes the module with the Safe that it will be attached to.
     * @param _safe The address of the Safe that this module will be attached to.
     */
    function initialize(address _safe) external {
        if (address(this) == _ORIGINAL_ADDRESS) {
            revert NotAClone();
        }
        if (address(safe) != address(0)) {
            revert ModuleAlreadyInitialized();
        }
        safe = Safe(payable(_safe));
    }

    /**
     * @notice Creates a new CoW AMM with the given parameters.
     * @param token0 The address of the first token in the pair.
     * @param token1 The address of the second token in the pair.
     * @param minTradedToken0 The minimum amount of token0 before the AMM attempts auto-rebalance.
     * @param priceOracle The address of the price oracle to use for the AMM.
     * @param priceOracleData The data to pass to the price oracle.
     * @param appData The app data to pass to the AMM.
     */
    function createAmm(
        IERC20 token0,
        IERC20 token1,
        uint256 minTradedToken0,
        address priceOracle,
        bytes calldata priceOracleData,
        bytes32 appData
    ) public onlySafe {
        // Always make sure the module is setup before doing anything
        _setup();

        // We can't create a new CoW AMM if there isn't anything to trade!
        if (token0.balanceOf(address(safe)) == 0 || token1.balanceOf(address(safe)) == 0) {
            revert TokenBalanceZero();
        }

        // Set the token allowances for the vault relayer
        _setAllowance(token0);
        _setAllowance(token1);

        // Prepare the data for the new CoW AMM
        ConstantProduct.Data memory data = ConstantProduct.Data({
            token0: token0,
            token1: token1,
            minTradedToken0: minTradedToken0,
            priceOracle: IPriceOracle(priceOracle),
            priceOracleData: priceOracleData,
            appData: appData
        });

        // Wrap the data in a conditional order
        IConditionalOrder.ConditionalOrderParams memory params = IConditionalOrder.ConditionalOrderParams({
            handler: HANDLER,
            salt: keccak256(abi.encodePacked(activeOrder, block.timestamp)),
            staticInput: abi.encode(data)
        });

        // Create the new CoW AMM
        _execute(address(COMPOSABLE_COW), 0, abi.encodeWithSelector(ComposableCoW.create.selector, params, true));

        // Set the new CoW AMM as the active order
        // Would be nice if the `ComposableCoW.create` returned the hash as it's
        // already calculated there and would prevent double-hashing and save some gas!
        activeOrder = COMPOSABLE_COW.hash(params);

        emit CowAmmCreated(activeOrder, address(token0), address(token1));
    }

    /**
     * @notice Replaces the active CoW AMM with a new one.
     * @param token0 The address of the first token in the pair.
     * @param token1 The address of the second token in the pair.
     * @param minTradedToken0 The minimum amount of token0 before the AMM attempts auto-rebalance.
     * @param priceOracle The address of the price oracle to use for the AMM.
     * @param priceOracleData The data to pass to the price oracle.
     * @param appData The app data to pass to the AMM.
     * @dev This function internally just calls `closeAmm` and then `createAmm`.
     */
    function replaceAmm(
        IERC20 token0,
        IERC20 token1,
        uint256 minTradedToken0,
        address priceOracle,
        bytes calldata priceOracleData,
        bytes32 appData
    ) external onlySafe {
        if (activeOrder != bytes32(0)) {
            closeAmm();
        }
        createAmm(token0, token1, minTradedToken0, priceOracle, priceOracleData, appData);
    }

    /**
     * @notice Closes the active CoW AMM.
     * @dev This function will call `ComposableCoW.remove` with the active order if there is one.
     */
    function closeAmm() public onlySafe {
        if (activeOrder != bytes32(0)) {
            _execute(address(COMPOSABLE_COW), 0, abi.encodeWithSelector(ComposableCoW.remove.selector, activeOrder));
            emit CowAmmClosed(activeOrder);
            activeOrder = bytes32(0);
        }
    }

    /**
     * @notice Conducts internal Safe setup to ensure that the creation of CoW AMMs is smooth.
     */
    function _setup() internal {
        _setFallbackHandler();
        _setComposableCowDomainVerifier();
    }

    /**
     * @notice A helper function for setting the fallback handler on the Safe as needed by ComposableCoW.
     */
    function _setFallbackHandler() internal {
        address fallbackHandler = abi.decode(safe.getStorageAt(uint256(_FALLBACK_HANDLER_STORAGE_SLOT), 1), (address));
        if (fallbackHandler != address(EXTENSIBLE_FALLBACK_HANDLER)) {
            _execute(
                address(safe), 0, abi.encodeWithSelector(safe.setFallbackHandler.selector, EXTENSIBLE_FALLBACK_HANDLER)
            );
        }
    }

    /**
     * @notice A helper function for setting the domain verifier in the `ExtensibleFallbackHandler` as needed by ComposableCoW.
     */
    function _setComposableCowDomainVerifier() internal {
        address domainVerifier = address(EXTENSIBLE_FALLBACK_HANDLER.domainVerifiers(safe, COW_DOMAIN_SEPARATOR));
        if (domainVerifier != address(COMPOSABLE_COW)) {
            _execute(
                address(safe), // MUST be the safe address
                0,
                abi.encodeWithSelector(
                    EXTENSIBLE_FALLBACK_HANDLER.setDomainVerifier.selector, COW_DOMAIN_SEPARATOR, COMPOSABLE_COW
                )
            );
        }
    }

    /**
     * @notice A helper function for executing a transaction from the module. This function is used to ensure that
     * execution is done consistently and that it never uses delegatecall.
     */
    function _execute(address to, uint256 value, bytes memory data) internal {
        safe.execTransactionFromModule(to, value, data, Enum.Operation.Call);
    }

    /**
     * @notice A helper function for setting ERC20 token allowances on the Sa fe
     */
    function _setAllowance(IERC20 token) internal {
        _execute(address(token), 0, abi.encodeWithSelector(token.approve.selector, VAULT_RELAYER, type(uint256).max));
    }
}
