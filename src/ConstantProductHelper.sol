// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.24;

import {IERC20, GPv2Order, ISettlement, ConstantProduct} from "./ConstantProduct.sol";
import {ICOWAMMPoolHelper, GPv2Interaction} from "./interfaces/ICOWAMMPoolHelper.sol";
import {GetTradeableOrder} from "./libraries/GetTradeableOrder.sol";
import {ConstantProductFactory} from "./ConstantProductFactory.sol";
import {Helper as LegacyHelper} from "./legacy/Helper.sol";

contract ConstantProductHelper is ICOWAMMPoolHelper, LegacyHelper {
    using GPv2Order for GPv2Order.Data;

    function factory() public view override returns (address) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        // Mainnet, gnosis, and sepolia. Addresses taken from networks.json
        if (chainId == 1) {
            return 0x8deEd8ED7C5fCB55884f13F121654Bb4bb7c8437;
        } else if (chainId == 100) {
            return 0x2AF6C59FC957D4a45ddBBD927fA30f7C5051F583;
        } else if (chainId == 11155111) {
            return 0xbD18758055dbe3ed37A2471394559aE97a5Da5c0;
        }

        revert("Unsupported chain");
    }

    ISettlement private constant SETTLEMENT = ISettlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);

    error InvalidArrayLength();

    /// @inheritdoc ICOWAMMPoolHelper
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

    /// @inheritdoc ICOWAMMPoolHelper
    function order(address pool, uint256[] calldata prices)
        external
        view
        returns (
            GPv2Order.Data memory _order,
            GPv2Interaction.Data[] memory preInteractions,
            GPv2Interaction.Data[] memory postInteractions,
            bytes memory sig
        )
    {
        if (prices.length != 2) {
            revert InvalidArrayLength();
        }

        if (!isLegacy(pool)) {
            // Standalone CoW AMMs (**non-Gnosis Safe Wallets**)
            if (!isCanonical(pool)) {
                revert("Pool is not canonical");
            }

            IERC20 token0 = ConstantProduct(pool).token0();
            IERC20 token1 = ConstantProduct(pool).token1();

            if (ConstantProduct(pool).tradingEnabled() == false) {
                revert ICOWAMMPoolHelper.PoolIsPaused();
            }

            _order = GetTradeableOrder.getTradeableOrder(
                GetTradeableOrder.GetTradeableOrderParams({
                    pool: pool,
                    token0: token0,
                    token1: token1,
                    priceNumerator: prices[0],
                    priceDenominator: prices[1],
                    appData: ConstantProduct(pool).APP_DATA()
                })
            );

            sig = abi.encode(_order);

            preInteractions = new GPv2Interaction.Data[](1);
            preInteractions[0] = GPv2Interaction.Data({
                target: pool,
                value: 0,
                callData: abi.encodeCall(ConstantProduct.commit, (_order.hash(SETTLEMENT.domainSeparator())))
            });
        } else {
            (_order, preInteractions, postInteractions, sig) = legacyOrder(pool, prices);
        }
    }

    /// @dev Take advantage of the mapping on the factory that is set to the owner's address for canonical pools.
    function isCanonical(address pool) private view returns (bool) {
        return ConstantProductFactory(factory()).owner(ConstantProduct(pool)) != address(0);
    }
}
