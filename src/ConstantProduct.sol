// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "lib/composable-cow/lib/@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/composable-cow/lib/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "lib/openzeppelin/contracts/utils/math/Math.sol";
import {ConditionalOrdersUtilsLib as Utils} from "lib/composable-cow/src/types/ConditionalOrdersUtilsLib.sol";
import {
    IConditionalOrderGenerator,
    IConditionalOrder,
    IERC165,
    GPv2Order
} from "lib/composable-cow/src/BaseConditionalOrder.sol";

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {ISettlement} from "./interfaces/ISettlement.sol";
import {IWatchtowerCustomErrors} from "./interfaces/IWatchtowerCustomErrors.sol";

/**
 * @title CoW AMM
 * @author CoW Protocol Developers
 * @dev Automated market maker based on the concept of function-maximising AMMs.
 * It relies on the CoW Protocol infrastructure to guarantee batch execution of
 * its orders.
 * Order creation and execution is based on the Composable CoW base contracts.
 */
contract ConstantProduct is IConditionalOrderGenerator {
    using SafeERC20 for IERC20;

    /// All data used by an order to validate the AMM conditions.
    struct TradingParams {
        /// The minimum amount of token0 that needs to be traded for an order
        /// to be created on getTradeableOrder.
        uint256 minTradedToken0;
        /// An onchain source for the price of the two tokens. The price should
        /// be expressed in terms of amount of token0 per amount of token1.
        IPriceOracle priceOracle;
        /// The data that needs to be provided to the price oracle to retrieve
        /// the relative price of the two tokens.
        bytes priceOracleData;
        /// The app data that must be used in the order.
        /// See `GPv2Order.Data` for more information on the app data.
        bytes32 appData;
    }

    /**
     * @notice The largest possible duration of any AMM order, starting from the
     * current block timestamp.
     */
    uint32 public constant MAX_ORDER_DURATION = 5 * 60;
    /**
     * @notice The value representing the absence of a commitment. It signifies
     * that the AMM will enforce that the order matches the order obtained from
     * calling `getTradeableOrder`.
     */
    bytes32 public constant EMPTY_COMMITMENT = bytes32(0);
    /**
     * @notice The value representing that no trading parameters are currently
     * accepted as valid by this contract, meaning that no trading can occur.
     */
    bytes32 public constant NO_TRADING = bytes32(0);

    /**
     * @notice The address of the CoW Protocol settlement contract. It is the
     * only address that can set commitments.
     */
    ISettlement public immutable solutionSettler;
    /**
     * @notice The first of the two tokens traded by this AMM.
     */
    IERC20 public immutable token0;
    /**
     * @notice The second of the two tokens traded by this AMM.
     */
    IERC20 public immutable token1;
    /**
     * @notice The address that can execute administrative tasks on this AMM,
     * as for example enabling/disabling trading or withdrawing funds.
     */
    address public immutable manager;
    /**
     * @notice The domain separator used for hashing CoW Protocol orders.
     */
    bytes32 public immutable solutionSettlerDomainSeparator;

    /**
     * @notice It associates every order owner to the only order hash that can
     * be validated by calling `verify`. The hash corresponding to the constant
     * `EMPTY_COMMITMENT` has special semantics, discussed in the related
     * documentation.
     */
    mapping(address => bytes32) public commitment;
    /**
     * The hash of the data describing which `TradingParams` currently apply
     * to this AMM. If this parameter is set to `NO_TRADING`, then the AMM
     * does not accept any order as valid.
     * If trading is enabled, then this value will be the [`hash`] of the only
     * admissible [`TradingParams`].
     */
    bytes32 public tradingParamsHash;

    /**
     * Emitted when the owner disables all trades by the AMM. Existing open
     * order will not be tradeable. Note that the AMM could resume trading with
     * different parameters at a later point.
     */
    event TradingDisabled();
    /**
     * Emitted when the owner enables the AMM to trade on CoW Protocol.
     * @param hash The hash of the trading parameters.
     * @param params Trading has been enabled for these parameters.
     */
    event TradingEnabled(bytes32 indexed hash, TradingParams params);

    /**
     * @notice This function is permissioned and can only be called by the
     * contract's manager.
     */
    error OnlyManagerCanCall();
    /**
     * @notice The `commit` function can only be called inside a CoW Swap
     * settlement. This error is thrown when the function is called from another
     * context.
     */
    error CommitOutsideOfSettlement();
    /**
     * @notice Error thrown when a solver tries to settle an AMM order on CoW
     * Protocol whose hash doesn't match the one that has been committed to in
     * the `commitment` mapping.
     */
    error OrderDoesNotMatchCommitmentHash();
    /**
     * @notice If an AMM order is settled and the AMM committment is set to
     * empty, then that order must match the output of `getTradeableOrder`.
     * This error is thrown when some of the parameters don't match the expected
     * ones.
     */
    error OrderDoesNotMatchDefaultTradeableOrder();

    modifier onlyManager() {
        if (manager != msg.sender) {
            revert OnlyManagerCanCall();
        }
        _;
    }

    /**
     * @param _solutionSettler The CoW Protocol contract used to settle user
     * orders on the current chain.
     * @param _token0 The first of the two tokens traded by this AMM.
     * @param _token1 The second of the two tokens traded by this AMM.
     */
    constructor(ISettlement _solutionSettler, IERC20 _token0, IERC20 _token1) {
        solutionSettler = _solutionSettler;
        solutionSettlerDomainSeparator = _solutionSettler.domainSeparator();

        approveUnlimited(_token0, msg.sender);
        approveUnlimited(_token1, msg.sender);
        manager = msg.sender;

        address vaultRelayer = _solutionSettler.vaultRelayer();
        approveUnlimited(_token0, vaultRelayer);
        approveUnlimited(_token1, vaultRelayer);

        token0 = _token0;
        token1 = _token1;
    }

    /**
     * @notice Once this function is called, it will be possible to trade with
     * this AMM on CoW Protocol.
     * @param tradingParams Trading is enabled with the parameters specified
     * here.
     */
    function enableTrading(TradingParams calldata tradingParams) external onlyManager {
        bytes32 _tradingParamsHash = hash(tradingParams);
        tradingParamsHash = _tradingParamsHash;
        emit TradingEnabled(_tradingParamsHash, tradingParams);
    }

    /**
     * @notice Disable any form of trading on CoW Protocol by this AMM.
     */
    function disableTrading() external onlyManager {
        tradingParamsHash = NO_TRADING;
        emit TradingDisabled();
    }

    /**
     * @notice Restricts a specific AMM to being able to trade only the order
     * with the specified hash.
     * @dev The commitment is used to enforce that exactly one AMM order is
     * valid when a CoW Protocol batch is settled.
     * @param owner the commitment applies to orders created by this address.
     * @param orderHash the order hash that will be enforced by the order
     * verification function.
     */
    function commit(address owner, bytes32 orderHash) public {
        if (msg.sender != address(solutionSettler)) {
            revert CommitOutsideOfSettlement();
        }
        commitment[owner] = orderHash;
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
     * @param owner the contract who is the owner of the order
     * @param staticInput the trading parameters of all discrete orders cut
     * from this conditional order
     * @return order the tradeable order for submission to the CoW Protocol API
     */
    function _getTradeableOrder(address owner, bytes calldata staticInput)
        internal
        view
        returns (GPv2Order.Data memory order)
    {
        ConstantProduct.TradingParams memory tradingParams = abi.decode(staticInput, (TradingParams));
        (uint256 priceNumerator, uint256 priceDenominator) =
            tradingParams.priceOracle.getPrice(address(token0), address(token1), tradingParams.priceOracleData);
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
        // Note on the order price: The buy amount is not optimal for the AMM
        // given the sell amount. This is intended because we want to force
        // solvers to maximize the surplus for this order with the price that
        // isn't the AMM best price.
        uint256 selfReserve0TimesPriceDenominator = selfReserve0 * priceDenominator;
        uint256 selfReserve1TimesPriceNumerator = selfReserve1 * priceNumerator;
        uint256 tradedAmountToken0;
        if (selfReserve1TimesPriceNumerator < selfReserve0TimesPriceDenominator) {
            sellToken = token0;
            buyToken = token1;
            sellAmount = sub(selfReserve0 / 2, Math.ceilDiv(selfReserve1TimesPriceNumerator, 2 * priceDenominator));
            buyAmount = Math.mulDiv(
                sellAmount,
                selfReserve1TimesPriceNumerator + (priceDenominator * sellAmount),
                priceNumerator * selfReserve0,
                Math.Rounding.Up
            );
            tradedAmountToken0 = sellAmount;
        } else {
            sellToken = token1;
            buyToken = token0;
            sellAmount = sub(selfReserve1 / 2, Math.ceilDiv(selfReserve0TimesPriceDenominator, 2 * priceNumerator));
            buyAmount = Math.mulDiv(
                sellAmount,
                selfReserve0TimesPriceDenominator + (priceNumerator * sellAmount),
                priceDenominator * selfReserve1,
                Math.Rounding.Up
            );
            tradedAmountToken0 = buyAmount;
        }

        if (tradedAmountToken0 < tradingParams.minTradedToken0) {
            revertPollAtNextBlock("traded amount too small");
        }

        order = GPv2Order.Data(
            sellToken,
            buyToken,
            GPv2Order.RECEIVER_SAME_AS_OWNER,
            sellAmount,
            buyAmount,
            Utils.validToBucket(MAX_ORDER_DURATION),
            tradingParams.appData,
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
        bytes32 orderHash,
        bytes32,
        bytes32,
        bytes calldata staticInput,
        bytes calldata,
        GPv2Order.Data calldata order
    ) external view override {
        _verify(owner, orderHash, staticInput, order);
    }

    /**
     * @dev Wrapper for the `verify` function with only the parameters that are
     * required for verification. Compared to implementing the logic inside
     * `verify`, it frees up some stack slots and reduces "stack too deep"
     * issues.
     * @param owner the contract who is the owner of the order
     * @param orderHash the hash of the current order as defined by the
     * `GPv2Order` library.
     * @param staticInput the trading parameters of all discrete orders cut
     * from this conditional order
     * @param order `GPv2Order.Data` of a discrete order to be verified.
     */
    function _verify(address owner, bytes32 orderHash, bytes calldata staticInput, GPv2Order.Data calldata order)
        internal
        view
    {
        requireMatchingCommitment(owner, orderHash, staticInput, order);
        ConstantProduct.TradingParams memory tradingParams = abi.decode(staticInput, (TradingParams));

        IERC20 sellToken = token0;
        IERC20 buyToken = token1;
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
        if (order.appData != tradingParams.appData) {
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
        // amounts for a constant-product curve AMM.
        if ((sellReserve - order.sellAmount) * order.buyAmount < buyReserve * order.sellAmount) {
            revert IConditionalOrder.OrderNotValid("received amount too low");
        }

        // No checks on:
        // - kind
        // - partiallyFillable
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(IConditionalOrderGenerator).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @notice Approves the spender to transfer an unlimited amount of tokens
     * and reverts if the approval was unsuccessful.
     * @param token The ERC-20 token to approve.
     * @param spender The address that can transfer on behalf of this contract.
     */
    function approveUnlimited(IERC20 token, address spender) internal {
        token.safeApprove(spender, type(uint256).max);
    }

    /**
     * @dev Computes the difference between the two input values. If it detects
     * an underflow, the function reverts with a custom error that informs the
     * watchtower to poll next.
     * If the function reverted with a standard underflow, the watchtower would
     * stop polling the order.
     * @param lhs The minuend of the subtraction
     * @param rhs The subtrahend of the subtraction
     * @return The difference of the two input values
     */
    function sub(uint256 lhs, uint256 rhs) internal view returns (uint256) {
        if (lhs < rhs) {
            revertPollAtNextBlock("subtraction underflow");
        }
        unchecked {
            return lhs - rhs;
        }
    }

    /**
     * @dev Reverts call execution with a custom error that indicates to the
     * watchtower to poll for new order when the next block is mined.
     */
    function revertPollAtNextBlock(string memory message) internal view {
        revert IWatchtowerCustomErrors.PollTryAtBlock(block.number + 1, message);
    }

    /**
     * @notice This function triggers a revert if either (1) the order hash does
     * not match the current commitment of the owner, or (2) in the case of a
     * commitment to `EMPTY_COMMITMENT`, the non-constant parameters of the
     * order from `getTradeableOrder` don't match those of the input order.
     * @param owner the contract that owns the order
     * @param orderHash the hash of the current order as defined by the
     * `GPv2Order` library.
     * @param tradingParams the trading parameters of all discrete orders cut
     * from this conditional order
     * @param order `GPv2Order.Data` of a discrete order to be verified
     */
    function requireMatchingCommitment(
        address owner,
        bytes32 orderHash,
        bytes calldata tradingParams,
        GPv2Order.Data calldata order
    ) internal view {
        bytes32 committedOrderHash = commitment[owner];
        if (orderHash != committedOrderHash) {
            if (committedOrderHash != EMPTY_COMMITMENT) {
                revert OrderDoesNotMatchCommitmentHash();
            }
            GPv2Order.Data memory computedOrder = _getTradeableOrder(owner, tradingParams);
            if (!matchFreeOrderParams(order, computedOrder)) {
                revert OrderDoesNotMatchDefaultTradeableOrder();
            }
        }
    }

    /**
     * @dev Computes an identifier that uniquely represents the parameters in
     * the function input parameters.
     * @param tradingParams Bytestring that decodes to `TradingParams`
     * @return The hash of the input parameter, intended to be used as a unique
     * identifier
     */
    function hash(TradingParams memory tradingParams) public pure returns (bytes32) {
        return keccak256(abi.encode(tradingParams));
    }

    /**
     * @notice Check if the parameters of the two input orders are the same,
     * with the exception of those parameters that have a single possible value
     * that passes the validation of `verify`.
     * @param lhs a CoW Swap order
     * @param rhs another CoW Swap order
     * @return true if the order parameters match, false otherwise
     */
    function matchFreeOrderParams(GPv2Order.Data calldata lhs, GPv2Order.Data memory rhs)
        internal
        pure
        returns (bool)
    {
        bool sameSellToken = lhs.sellToken == rhs.sellToken;
        bool sameBuyToken = lhs.buyToken == rhs.buyToken;
        bool sameSellAmount = lhs.sellAmount == rhs.sellAmount;
        bool sameBuyAmount = lhs.buyAmount == rhs.buyAmount;
        bool sameValidTo = lhs.validTo == rhs.validTo;
        bool sameKind = lhs.kind == rhs.kind;
        bool samePartiallyFillable = lhs.partiallyFillable == rhs.partiallyFillable;

        // The following parameters are untested:
        // - receiver
        // - appData
        // - feeAmount
        // - sellTokenBalance
        // - buyTokenBalance

        return sameSellToken && sameBuyToken && sameSellAmount && sameBuyAmount && sameValidTo && sameKind
            && samePartiallyFillable;
    }
}
