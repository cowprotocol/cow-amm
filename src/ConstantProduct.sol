// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "lib/composable-cow/lib/@openzeppelin/contracts/interfaces/IERC20.sol";
import {Math} from "lib/composable-cow/lib/@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV2Pair} from "lib/uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {ConditionalOrdersUtilsLib as Utils} from "lib/composable-cow/src/types/ConditionalOrdersUtilsLib.sol";
import {
    IConditionalOrderGenerator,
    IConditionalOrder,
    IERC165,
    GPv2Order
} from "lib/composable-cow/src/BaseConditionalOrder.sol";

/**
 * @title CoW AMM
 * @author CoW Protocol Developers
 * @dev Automated market maker based on the concept of function-maximising AMMs.
 * It relies on the CoW Protocol infrastructure to guarantee batch execution of
 * its orders.
 * Order creation and execution is based on the Composable CoW base contracts.
 */
contract ConstantProduct is IConditionalOrderGenerator {
    uint32 public constant MAX_ORDER_DURATION = 5 * 60;

    /// All data used by an order to validate the AMM conditions.
    struct Data {
        /// A Uniswap v2 pair. This is used to determine the tokens traded by
        /// the AMM, and also use to establish the reference price used when
        /// computing a valid tradable order.
        IUniswapV2Pair referencePair;
        /// The app data that must be used in the order.
        /// See `GPv2Order.Data` for more information on the app data.
        bytes32 appData;
    }

    /**
     * @notice The order returned by this function is the order that needs to be
     * executed for the price on the owner AMM to match that of the reference
     * pair.
     * @inheritdoc IConditionalOrderGenerator
     */
    function getTradeableOrder(address owner, address, bytes32, bytes calldata staticInput, bytes calldata)
        public
        view
        override
        returns (GPv2Order.Data memory)
    {
        return _getTradeableOrder(owner, staticInput);
    }

    /**
     * @dev Wrapper for the `getTradeableOrder` function with only the
     * parameters that are required for order creation. Compared to implementing
     * the logic inside the original function, it frees up some stack slots and
     * reduces "stack too deep" issues.
     * @dev We are not interested in the gas efficiency of this function because
     * it is not supposed to be called by a call in the blockchain.
     * @param owner the contract who is the owner of the order
     * @param staticInput the static input for all discrete orders cut from this
     * conditional order
     * @return order the tradeable order for submission to the CoW Protocol API
     */
    function _getTradeableOrder(address owner, bytes calldata staticInput)
        internal
        view
        returns (GPv2Order.Data memory order)
    {
        ConstantProduct.Data memory data = abi.decode(staticInput, (Data));
        IERC20 token0 = IERC20(data.referencePair.token0());
        IERC20 token1 = IERC20(data.referencePair.token1());
        (uint256 uniswapReserve0, uint256 uniswapReserve1,) = data.referencePair.getReserves();
        (uint256 selfReserve0, uint256 selfReserve1) = (token0.balanceOf(owner), token1.balanceOf(owner));

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
        if (uniswapReserve0 * selfReserve1 < uniswapReserve1 * selfReserve0) {
            sellToken = token0;
            buyToken = token1;
            sellAmount = selfReserve0 / 2 - Math.ceilDiv(uniswapReserve0 * selfReserve1, 2 * uniswapReserve1);
            buyAmount = Math.ceilDiv(uniswapReserve1 * selfReserve0, 2 * uniswapReserve0) - selfReserve1 / 2;
        } else {
            sellToken = token1;
            buyToken = token0;
            sellAmount = selfReserve1 / 2 - Math.ceilDiv(uniswapReserve1 * selfReserve0, 2 * uniswapReserve0);
            buyAmount = Math.ceilDiv(uniswapReserve0 * selfReserve1, 2 * uniswapReserve1) - selfReserve0 / 2;
        }

        order = GPv2Order.Data(
            sellToken,
            buyToken,
            GPv2Order.RECEIVER_SAME_AS_OWNER,
            sellAmount,
            buyAmount,
            Utils.validToBucket(MAX_ORDER_DURATION),
            data.appData,
            0,
            GPv2Order.KIND_SELL,
            true,
            GPv2Order.BALANCE_ERC20,
            GPv2Order.BALANCE_ERC20
        );
    }

    /**
     * @inheritdoc IConditionalOrder
     * @dev Most parameters are ignored: we only need to validate the order with
     * the current reserves and the validated order parameters.
     */
    function verify(
        address owner,
        address,
        bytes32,
        bytes32,
        bytes32,
        bytes calldata staticInput,
        bytes calldata,
        GPv2Order.Data calldata order
    ) external view override {
        _verify(owner, staticInput, order);
    }

    /**
     * @dev Wrapper for the `verify` function with only the parameters that are
     * required for verification. Compared to implementing the logic inside
     * `verify`, it frees up some stack slots and reduces "stack too deep"
     * issues.
     * @param owner the contract who is the owner of the order
     * @param staticInput the static input for all discrete orders cut from this
     * conditional order
     * @param order `GPv2Order.Data` of a discrete order to be verified.
     */
    function _verify(address owner, bytes calldata staticInput, GPv2Order.Data calldata order) internal view {
        ConstantProduct.Data memory data = abi.decode(staticInput, (Data));

        IERC20 sellToken = IERC20(data.referencePair.token0());
        IERC20 buyToken = IERC20(data.referencePair.token1());
        uint256 sellReserve = sellToken.balanceOf(owner);
        uint256 buyReserve = buyToken.balanceOf(owner);
        if (order.sellToken != sellToken) {
            if (order.sellToken != buyToken) {
                revert IConditionalOrder.OrderNotValid("invalid sell token");
            }
            (sellToken, buyToken) = (buyToken, sellToken);
            (sellReserve, buyReserve) = (buyReserve, sellReserve);
        }
        if (order.buyToken != buyToken) {
            revert IConditionalOrder.OrderNotValid("invalid buy token");
        }

        if (order.receiver != GPv2Order.RECEIVER_SAME_AS_OWNER) {
            revert IConditionalOrder.OrderNotValid("receiver must be zero address");
        }
        // We add a maximum duration to avoid spamming the orderbook and force
        // an order refresh if the order is old.
        if (order.validTo > block.timestamp + MAX_ORDER_DURATION) {
            revert IConditionalOrder.OrderNotValid("validity too far in the future");
        }
        if (order.appData != data.appData) {
            revert IConditionalOrder.OrderNotValid("invalid appData");
        }
        if (order.feeAmount != 0) {
            revert IConditionalOrder.OrderNotValid("fee amount must be zero");
        }
        if (order.buyTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert IConditionalOrder.OrderNotValid("buyTokenBalance must be erc20");
        }
        if (order.sellTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert IConditionalOrder.OrderNotValid("sellTokenBalance must be erc20");
        }
        // These are the checks needed to satisfy the conditions on in/out
        // amounts for the function-maximising AMM.
        if ((sellReserve - 2 * order.sellAmount) * order.buyAmount < buyReserve * order.sellAmount) {
            revert IConditionalOrder.OrderNotValid("received amount too low");
        }

        // No checks on:
        //bytes32 kind;
        //bool partiallyFillable;
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(IConditionalOrderGenerator).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
