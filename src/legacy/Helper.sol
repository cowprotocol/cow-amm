// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.24;

import {ICOWAMMPoolHelper, GPv2Interaction} from "../interfaces/ICOWAMMPoolHelper.sol";
import {IERC20, IConditionalOrder, ISettlement, GPv2Order} from "../ConstantProduct.sol";
import {GetTradeableOrder} from "../libraries/GetTradeableOrder.sol";

import {Snapshot} from "./Snapshot.sol";

abstract contract Helper is Snapshot {
    using GPv2Order for GPv2Order.Data;

    ISettlement private constant SETTLEMENT = ISettlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);

    // --- contracts required for checking if a cow amm remains valid

    // keccak256("fallback_manager.handler.address")
    bytes32 internal constant FALLBACK_HANDLER_STORAGE_SLOT =
        0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;
    address internal constant EXTENSIBLE_FALLBACK_HANDLER = address(0x2f55e8b20D0B9FEFA187AA7d00B6Cbe563605bF5);
    IComposableCOW private constant COMPOSABLE_COW = IComposableCOW(0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74);

    // Data that was broadcast for off-chain consumption by legacy CoW AMMs.
    // All this data **MUST** be stored as this is used when creating the
    // signature.
    struct LegacyTradingParams {
        IERC20 token0;
        IERC20 token1;
        uint256 minTradedToken0;
        address priceOracle;
        bytes priceOracleData;
        bytes32 appData;
    }

    function legacyOrder(address pool, uint256[] calldata prices)
        internal
        view
        returns (
            GPv2Order.Data memory _order,
            GPv2Interaction.Data[] memory preInteractions,
            GPv2Interaction.Data[] memory postInteractions,
            bytes memory sig
        )
    {
        // Legacy CoW AMMs (**Gnosis Safe Wallets**)
        if (!isLegacyEnabled(pool)) revert ICOWAMMPoolHelper.PoolIsClosed();

        (IERC20[] memory _tokens, IConditionalOrder.ConditionalOrderParams memory params) = getLegacyAMMInfo(pool);
        LegacyTradingParams memory tradingParams = abi.decode(params.staticInput, (LegacyTradingParams));
        _order = GetTradeableOrder.getTradeableOrder(
            GetTradeableOrder.GetTradeableOrderParams({
                pool: pool,
                token0: _tokens[0],
                token1: _tokens[1],
                priceNumerator: prices[0],
                priceDenominator: prices[1],
                appData: tradingParams.appData
            })
        );

        bytes32 domainSeparator = SETTLEMENT.domainSeparator();

        sig = abi.encodeWithSignature(
            "safeSignature(bytes32,bytes32,bytes,bytes)",
            domainSeparator,
            GPv2Order.TYPE_HASH,
            abi.encode(_order),
            abi.encode(
                IExtensibleFallbackHandler.PayloadStruct({params: params, offchainInput: "", proof: new bytes32[](0)})
            )
        );

        // For legacy, we need to do a pre-interaction to set the commitment.
        preInteractions = new GPv2Interaction.Data[](1);

        // Here we use a small ABI code snippet as this from severely legacy code.
        preInteractions[0] = GPv2Interaction.Data({
            target: address(params.handler),
            value: 0,
            callData: abi.encodeWithSignature("commit(address,bytes32)", pool, _order.hash(domainSeparator))
        });

        // For legacy, we need to do a post-interaction to reset the commitment
        // as the legacy code was deployed pre-dencun.
        // The `EMPTY_COMMITMENT` as seen at
        // https://github.com/cowprotocol/cow-amm/blob/91b25d6f54784783e694c7fdbd081b96b4991ae9/src/ConstantProduct.sol
        postInteractions = new GPv2Interaction.Data[](1);
        postInteractions[0] = GPv2Interaction.Data({
            target: address(params.handler),
            value: 0,
            callData: abi.encodeWithSignature("commit(address,bytes32)", pool, bytes32(0))
        });
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
        success = success && COMPOSABLE_COW.singleOrders(amm, keccak256(abi.encode(params)));
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
    function singleOrders(address safe, bytes32 hash) external view returns (bool);
}
