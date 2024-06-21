// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.24;

import {Math} from "lib/openzeppelin/contracts/utils/math/Math.sol";
import {ConditionalOrdersUtilsLib as Utils} from "lib/composable-cow/src/types/ConditionalOrdersUtilsLib.sol";
import {IConditionalOrder, IERC20, ISettlement, GPv2Order, ConstantProduct} from "./ConstantProduct.sol";
import {ConstantProductFactory} from "./ConstantProductFactory.sol";
import {ConstantProductSnapshot} from "./ConstantProductSnapshot.sol";
import {ICOWAMMPoolHelper, GPv2Interaction} from "./interfaces/ICOWAMMPoolHelper.sol";

contract ConstantProductHelper is ICOWAMMPoolHelper, ConstantProductSnapshot {
    using GPv2Order for GPv2Order.Data;

    address public constant factory = address(0);

    /**
     * @notice The largest possible duration of any AMM order, starting from the
     * current block timestamp.
     */
    uint32 public constant MAX_ORDER_DURATION = 5 * 60;

    error InvalidArrayLength();

    /**
     * @inheritdoc ICOWAMMPoolHelper
     */
    function tokens(address pool) external view returns (address[] memory _tokens) {
        _tokens = new address[](2);
        if (!isLegacy(pool)) {
            _tokens[0] = address(ConstantProduct(pool).token0());
            _tokens[1] = address(ConstantProduct(pool).token1());
        } else {
            (IERC20[] memory legacyTokens,) = getLegacyAMMInfo(pool);
            _tokens[0] = address(legacyTokens[0]);
            _tokens[1] = address(legacyTokens[1]);
        }
    }

    /**
     * @inheritdoc ICOWAMMPoolHelper
     */
    function order(address pool, uint256[] calldata prices)
        external
        view
        returns (GPv2Order.Data memory, GPv2Interaction.Data[] memory, bytes memory)
    {
        if (prices.length != 2) {
            revert InvalidArrayLength();
        }

        GPv2Order.Data memory _order;
        GPv2Interaction.Data[] memory interactions = new GPv2Interaction.Data[](1);
        bytes memory sig;

        if (!isLegacy(pool)) {
            // Standalone CoW AMMs (**non-Gnosis Safe Wallets**)
            if (!isCanonical(pool)) revert("Pool is not canonical");

            IERC20 token0 = ConstantProduct(pool).token0();
            IERC20 token1 = ConstantProduct(pool).token1();

            revert("Check for the pool having trading enabled or not");

            _order = getTradeableOrder(
                GetTradeableOrderParams({
                    pool: pool,
                    token0: token0,
                    token1: token1,
                    priceNumerator: prices[0],
                    priceDenominator: prices[1],
                    appData: bytes32(0)
                })
            );

            sig = abi.encode(_order);
            interactions[0] = GPv2Interaction.Data({
                target: pool,
                value: 0,
                callData: abi.encodeCall(ConstantProduct.commit, (_order.hash(SETTLEMENT.domainSeparator())))
            });
        } else {
            // Legacy CoW AMMs (**Gnosis Safe Wallets**)
            if (!isLegacyEnabled(pool)) revert ICOWAMMPoolHelper.PoolIsClosed();

            (IERC20[] memory _tokens, IConditionalOrder.ConditionalOrderParams memory params) = getLegacyAMMInfo(pool);
            LegacyTradingParams memory tradingParams = abi.decode(params.staticInput, (LegacyTradingParams));
            _order = getTradeableOrder(
                GetTradeableOrderParams({
                    pool: pool,
                    token0: _tokens[0],
                    token1: _tokens[1],
                    priceNumerator: prices[0],
                    priceDenominator: prices[1],
                    appData: tradingParams.appData
                })
            );

            sig = abi.encodeWithSignature(
                "safeSignature(bytes32,bytes32,bytes,bytes)",
                SETTLEMENT.domainSeparator(),
                GPv2Order.TYPE_HASH,
                abi.encode(_order),
                abi.encode(
                    IExtensibleFallbackHandler.PayloadStruct({
                        params: params,
                        offchainInput: "",
                        proof: new bytes32[](0)
                    })
                )
            );

            // Here we use a small ABI code snippet as this from severely legacy code.
            interactions[0] = GPv2Interaction.Data({
                target: address(params.handler),
                value: 0,
                callData: abi.encodeWithSignature(
                    "commit(address,bytes32)", pool, _order.hash(SETTLEMENT.domainSeparator())
                )
            });
        }

        return (_order, interactions, sig);
    }

    /// @dev Avoid stack too deep errors with `getTradeableOrder`.
    struct GetTradeableOrderParams {
        address pool;
        IERC20 token0;
        IERC20 token1;
        uint256 priceNumerator;
        uint256 priceDenominator;
        bytes32 appData;
    }

    function getTradeableOrder(GetTradeableOrderParams memory params)
        internal
        view
        returns (GPv2Order.Data memory order_)
    {
        (uint256 selfReserve0, uint256 selfReserve1) =
            (params.token0.balanceOf(params.pool), params.token1.balanceOf(params.pool));

        IERC20 sellToken;
        IERC20 buyToken;
        uint256 sellAmount;
        uint256 buyAmount;
        // Note on rounding: we want to round down the sell amount and up the
        // buy amount. This is because the math for the order makes it lie
        // precisely on the AMM curve, and a rounding error to the other way
        // could cause a valid order to become invalid.
        // Note on the if condition: it guarantees that sellAmount is positive
        // in the corresponding branch (it would be negative in the other). This
        // excludes rounding errors: in this case, the function could revert but
        // the amounts involved would be just a few atoms, so we accept that no
        // order will be available.
        // Note on the order price: The buy amount is not optimal for the AMM
        // given the sell amount. This is intended because we want to force
        // solvers to maximize the surplus for this order with the price that
        // isn't the AMM best price.
        uint256 selfReserve0TimesPriceDenominator = selfReserve0 * params.priceDenominator;
        uint256 selfReserve1TimesPriceNumerator = selfReserve1 * params.priceNumerator;
        uint256 tradedAmountToken0;
        if (selfReserve1TimesPriceNumerator < selfReserve0TimesPriceDenominator) {
            sellToken = params.token0;
            buyToken = params.token1;
            sellAmount = selfReserve0 / 2 - Math.ceilDiv(selfReserve1TimesPriceNumerator, 2 * params.priceDenominator);
            buyAmount = Math.mulDiv(
                sellAmount,
                selfReserve1TimesPriceNumerator + (params.priceDenominator * sellAmount),
                params.priceNumerator * selfReserve0,
                Math.Rounding.Up
            );
            tradedAmountToken0 = sellAmount;
        } else {
            sellToken = params.token1;
            buyToken = params.token0;
            sellAmount = selfReserve1 / 2 - Math.ceilDiv(selfReserve0TimesPriceDenominator, 2 * params.priceNumerator);
            buyAmount = Math.mulDiv(
                sellAmount,
                selfReserve0TimesPriceDenominator + (params.priceNumerator * sellAmount),
                params.priceDenominator * selfReserve1,
                Math.Rounding.Up
            );
            tradedAmountToken0 = buyAmount;
        }

        order_ = GPv2Order.Data(
            sellToken,
            buyToken,
            GPv2Order.RECEIVER_SAME_AS_OWNER,
            sellAmount,
            buyAmount,
            Utils.validToBucket(MAX_ORDER_DURATION),
            params.appData,
            0,
            GPv2Order.KIND_SELL,
            true,
            GPv2Order.BALANCE_ERC20,
            GPv2Order.BALANCE_ERC20
        );
    }

    /// @dev Take advantage of the mapping on the factory that is set to the owner's address for canonical pools.
    function isCanonical(address pool) public view returns (bool) {
        return ConstantProductFactory(factory).owner(ConstantProduct(pool)) != address(0);
    }

    /// --- legacy handling

    // --- contracts required for checking if a cow amm remains valid

    // keccak256("fallback_manager.handler.address")
    bytes32 internal constant FALLBACK_HANDLER_STORAGE_SLOT =
        0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;
    address internal constant EXTENSIBLE_FALLBACK_HANDLER = address(0x2f55e8b20D0B9FEFA187AA7d00B6Cbe563605bF5);
    ISettlement private constant SETTLEMENT = ISettlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);
    IComposableCOW private constant COMPOSABLE_COW = IComposableCOW(0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74);

    /**
     * Data that was broadcast for off-chain consumption by legacy CoW AMMs.
     * All this data **MUST** be stored as this is used when creating the
     * signature.
     */
    struct LegacyTradingParams {
        IERC20 token0;
        IERC20 token1;
        uint256 minTradedToken0;
        address priceOracle;
        bytes priceOracleData;
        bytes32 appData;
    }

    /// @dev Given an `amm`, check if it is in the hardcoded list of legacy CoW AMMs.
    function isLegacy(address amm) public view returns (bool) {
        return getSnapshot(amm).length > 0;
    }

    /// @dev Given an `amm` that is is known to be legacy, check if it is still valid.
    function isLegacyEnabled(address amm) public view returns (bool success) {
        // First check the safe has `ExtensibleFallbackHandler` configured as the fallback handler
        address fallbackHandler =
            abi.decode(IStorageViewer(amm).getStorageAt(uint256(FALLBACK_HANDLER_STORAGE_SLOT), 1), (address));
        success = fallbackHandler == EXTENSIBLE_FALLBACK_HANDLER;

        // Next check that the safe has delegated the domain verifier to ComposableCoW
        success = success
            && IExtensibleFallbackHandler(EXTENSIBLE_FALLBACK_HANDLER).domainVerifiers(amm, SETTLEMENT.domainSeparator())
                == address(COMPOSABLE_COW);

        // Finally check that the singleOrder(h(params)) is true
        IConditionalOrder.ConditionalOrderParams memory params =
            abi.decode(getSnapshot(amm), (IConditionalOrder.ConditionalOrderParams));
        success = success && COMPOSABLE_COW.singleOrders(amm, COMPOSABLE_COW.hash(params));
    }

    /// @dev Returns the tokens and the IConditionalOrder.ConditionalOrderParams for a legacy CoW AMM.
    function getLegacyAMMInfo(address pool)
        internal
        view
        returns (IERC20[] memory _tokens, IConditionalOrder.ConditionalOrderParams memory params)
    {
        // Get the ComposableCoW parameters
        params = abi.decode(getSnapshot(pool), (IConditionalOrder.ConditionalOrderParams));
        LegacyTradingParams memory tradingParams = abi.decode(params.staticInput, (LegacyTradingParams));

        _tokens = new IERC20[](2);
        _tokens[0] = tradingParams.token0;
        _tokens[1] = tradingParams.token1;
    }

    function hashHelper(GPv2Order.Data memory _order) external view returns (bytes32) {
        return _order.hash(SETTLEMENT.domainSeparator());
    }
}

// --- interfaces for legacy handling

interface IStorageViewer {
    function getStorageAt(uint256 offset, uint256 length) external view returns (bytes memory);
}

interface IExtensibleFallbackHandler {
    struct PayloadStruct {
        bytes32[] proof;
        IConditionalOrder.ConditionalOrderParams params;
        bytes offchainInput;
    }

    function domainVerifiers(address safe, bytes32 domainSeparator) external view returns (address);
}

interface IComposableCOW {
    function hash(IConditionalOrder.ConditionalOrderParams memory params) external view returns (bytes32);
    function singleOrders(address safe, bytes32 hash) external view returns (bool);
}
