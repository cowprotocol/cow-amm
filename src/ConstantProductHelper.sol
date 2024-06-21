// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.24;

import {Math} from "lib/openzeppelin/contracts/utils/math/Math.sol";
import {ConditionalOrdersUtilsLib as Utils} from "lib/composable-cow/src/types/ConditionalOrdersUtilsLib.sol";
import {IConditionalOrder, IERC20, ISettlement, GPv2Order, ConstantProduct} from "./ConstantProduct.sol";
import {ConstantProductFactory} from "./ConstantProductFactory.sol";
import {ICOWAMMPoolHelper, GPv2Interaction} from "./interfaces/ICOWAMMPoolHelper.sol";

contract ConstantProductHelper is ICOWAMMPoolHelper {
    using GPv2Order for GPv2Order.Data;

    // address public constant factory = address(0);
    function factory() public view returns (address) {
        revert("Set this to deployed factory");
    }

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
            sellAmount =
                selfReserve0 / 2 - Math.ceilDiv(selfReserve1TimesPriceNumerator, 2 * params.priceDenominator);
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
            sellAmount =
                selfReserve1 / 2 - Math.ceilDiv(selfReserve0TimesPriceDenominator, 2 * params.priceNumerator);
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
        return ConstantProductFactory(factory).owner(pool) != address(0);
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
        return getLegacySafeCOWAMMSnapshot(amm).length > 0;
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
            abi.decode(getLegacySafeCOWAMMSnapshot(amm), (IConditionalOrder.ConditionalOrderParams));
        success = success && COMPOSABLE_COW.singleOrders(amm, COMPOSABLE_COW.hash(params));
    }

    /// @dev Returns the tokens and the IConditionalOrder.ConditionalOrderParams for a legacy CoW AMM.
    function getLegacyAMMInfo(address pool)
        internal
        view
        returns (IERC20[] memory _tokens, IConditionalOrder.ConditionalOrderParams memory params)
    {
        // Get the ComposableCoW parameters
        params = abi.decode(getLegacySafeCOWAMMSnapshot(pool), (IConditionalOrder.ConditionalOrderParams));
        LegacyTradingParams memory tradingParams = abi.decode(params.staticInput, (LegacyTradingParams));

        _tokens = new IERC20[](2);
        _tokens[0] = tradingParams.token0;
        _tokens[1] = tradingParams.token1;
    }

    /// @dev Returns the IConditionalOrder.ConditionalOrderParams for a legacy CoW AMM. Returns bytes(0) if the pool
    /// isn't found in the snapshot data.
    function getLegacySafeCOWAMMSnapshot(address amm) internal view returns (bytes memory) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        if (chainId == 1) {
            // Ethereum mainnet generated snapshot.
            if (amm == 0xE96b516d40DB176F6b120fd8ff025De6b7bB32Ee) {
                return
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000034323b933096534e43958f6c7bf44f2bb59424da023a9026beba2be0b9d1dc6615e457e7b59d2e482b8815cba9699aa81c7aaf5c000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000090cec99ceefa4000000000000000000000000ad37fe3ddedf8cdee1022da1b17412cfb649559600000000000000000000000000000000000000000000000000000000000000c04d821ddc9d656177dad4d5c2f76a4bff2ed514ff69fa4aa4fd869d6e98d55c8900000000000000000000000000000000000000000000000000000000000000206f0ed6f346007563d3266de350d174a831bde0ca0001000000000000000005db";
            } else if (amm == 0xC6B13D5E662FA0458F03995bCb824a1934aA895f) {
                return
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000034323b933096534e43958f6c7bf44f2bb59424da932542294ff270a8bbdbe1fb921de3d09c9749dc35627361fc17c44b9b026b810000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000200000000000000000000000008390a1da07e376ef7add4be859ba74fb83aa02d5000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000aec1c94998000000000000000000000000573cc0c800048f94e022463b9214d92c2d65e97b00000000000000000000000000000000000000000000000000000000000000c04d821ddc9d656177dad4d5c2f76a4bff2ed514ff69fa4aa4fd869d6e98d55c89000000000000000000000000000000000000000000000000000000000000002000000000000000000000000069c66beafb06674db41b22cfc50c34a93b8d82a2";
            } else if (amm == 0xBEEf5aFE88eF73337e5070aB2855d37dBF5493A4) {
                return
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000034323b933096534e43958f6c7bf44f2bb59424da0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000def1ca1fb7fbcdc777520aa7f396b4e015f497ab000000000000000000000000000000000000000000000000025bf6196bd10000000000000000000000000000ad37fe3ddedf8cdee1022da1b17412cfb649559600000000000000000000000000000000000000000000000000000000000000c0d661a16b0e85eadb705cf5158132b5dd1ebc0a49929ef68097698d15e2a4e3b40000000000000000000000000000000000000000000000000000000000000020de8c195aa41c11a0c4787372defbbddaa31306d2000200000000000000000181";
            } else if (amm == 0x7c420c3a33AA87bf0c6327930b93376079e06a18) {
                return
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000034323b933096534e43958f6c7bf44f2bb59424da6400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000005f5e100000000000000000000000000573cc0c800048f94e022463b9214d92c2d65e97b00000000000000000000000000000000000000000000000000000000000000c0924f5e36ae70c8cdad505bc4807be76099024df2520e89d14478e42c5208444100000000000000000000000000000000000000000000000000000000000000200000000000000000000000003041cbd36888becc7bbcbc0045e3b1f144466f5f";
            } else if (amm == 0xd7cb8Cc1B56356BB7b78D02E785eAD28e2158660) {
                return
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000034323b933096534e43958f6c7bf44f2bb59424da80ba533f014ef4238ab7ad203c0aeacbf30a71c0346140db77c43ae3121afadd000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000aea46a60368a7bd060eec7df8cba43b7ef41ad85000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000336632e53c8ecf04000000000000000000000000573cc0c800048f94e022463b9214d92c2d65e97b00000000000000000000000000000000000000000000000000000000000000c04d821ddc9d656177dad4d5c2f76a4bff2ed514ff69fa4aa4fd869d6e98d55c8900000000000000000000000000000000000000000000000000000000000000200000000000000000000000004042a04c54ef133ac2a3c93db69d43c6c02a330b";
            } else if (amm == 0x301076c36E034948A747BB61bAB9CD03f62672e3) {
                return
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000034323b933096534e43958f6c7bf44f2bb59424daca44b6a304baa16d11b6db07066c1276b1273ee3f94590bbd03201a61882af9a000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000098cb76000000000000000000000000573cc0c800048f94e022463b9214d92c2d65e97b00000000000000000000000000000000000000000000000000000000000000c04d821ddc9d656177dad4d5c2f76a4bff2ed514ff69fa4aa4fd869d6e98d55c890000000000000000000000000000000000000000000000000000000000000020000000000000000000000000b4e16d0168e52d35cacd2c6185b44281ec28c9dc";
            } else if (amm == 0xB3Bf81714f704720dcB0351fF0d42eCa61B069FC) {
                return
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000034323b933096534e43958f6c7bf44f2bb59424dad003838829115f5d9ff3ed69c8d2b4b26e10eb1a79331206c28fbb4734390a5e000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000808507121b80c02388fad14726482e061b8da827000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000189b23422a9b84d8000000000000000000000000ad37fe3ddedf8cdee1022da1b17412cfb649559600000000000000000000000000000000000000000000000000000000000000c04d821ddc9d656177dad4d5c2f76a4bff2ed514ff69fa4aa4fd869d6e98d55c890000000000000000000000000000000000000000000000000000000000000020fd1cf6fd41f229ca86ada0584c63c49c3d66bbc9000200000000000000000438";
            } else if (amm == 0x6F37Bcb7aD3E6c9309c2c7698f25E0653bfddf46) {
                return
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000034323b933096534e43958f6c7bf44f2bb59424da5d6460e689a50f6b3ffed85c398fb9ff776af99c268fc25b66fab3c73079bbdb000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000989680000000000000000000000000ad37fe3ddedf8cdee1022da1b17412cfb649559600000000000000000000000000000000000000000000000000000000000000c04d821ddc9d656177dad4d5c2f76a4bff2ed514ff69fa4aa4fd869d6e98d55c89000000000000000000000000000000000000000000000000000000000000002067f117350eab45983374f4f83d275d8a5d62b1bf0001000000000000000004f2";
            } else if (amm == 0x027e1CbF2C299CBa5eB8A2584910d04f1A8Aa403) {
                return
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000034323b933096534e43958f6c7bf44f2bb59424dac5a0e756ac88c1d3a4c41900d977fe93c2d34fc95a00ca3e84eb4c6b50faf949000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000005afe3855358e112b5647b952709e6165e1c1eeee000000000000000000000000000000000000000000000000016345785d8a0000000000000000000000000000573cc0c800048f94e022463b9214d92c2d65e97b00000000000000000000000000000000000000000000000000000000000000c04d821ddc9d656177dad4d5c2f76a4bff2ed514ff69fa4aa4fd869d6e98d55c8900000000000000000000000000000000000000000000000000000000000000200000000000000000000000002e7e978da0c53404a8cf66ed4ba2c7706c07b62a";
            } else if (amm == 0x9941fD7dB2003308E7Ee17B04400012278F12aC6) {
                return
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000034323b933096534e43958f6c7bf44f2bb59424da559d5fda20be80608e4d5ea1b41e6b9330efca7934beb094281dd4d8f4889374000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000514910771af9ca656af840dff83e8264ecf986ca000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000079ef7f110fdfae4000000000000000000000000ad37fe3ddedf8cdee1022da1b17412cfb649559600000000000000000000000000000000000000000000000000000000000000c04d821ddc9d656177dad4d5c2f76a4bff2ed514ff69fa4aa4fd869d6e98d55c890000000000000000000000000000000000000000000000000000000000000020e99481dc77691d8e2456e5f3f61c1810adfc1503000200000000000000000018";
            } else if (amm == 0xeFF88AfF44c361d7205776cf16ec303C6262a4Af) {
                return
                hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000034323b933096534e43958f6c7bf44f2bb59424da2e8e6822f26439971f4b155fbd184cd8b8f2d595c40d8aec36b09e04c5004ad60000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000200000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000068155a43676e0000000000000000000000000000573cc0c800048f94e022463b9214d92c2d65e97b00000000000000000000000000000000000000000000000000000000000000c04d821ddc9d656177dad4d5c2f76a4bff2ed514ff69fa4aa4fd869d6e98d55c890000000000000000000000000000000000000000000000000000000000000020000000000000000000000000c3d03e4f041fd4cd388c549ee2a29a9e5075882f";
            }
        } else if (chainId == 100) {
            // Gnosis chain generated snapshot.
            revert("Unimplemented");
        }

        return hex"";
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
