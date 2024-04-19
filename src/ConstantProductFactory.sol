// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ComposableCoW, IConditionalOrder} from "lib/composable-cow/src/ComposableCoW.sol";
import {SafeERC20} from "lib/composable-cow/lib/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ConstantProduct, IERC20, ISettlement, GPv2Order, IPriceOracle} from "./ConstantProduct.sol";

/**
 * @title CoW AMM Factory
 * @author CoW Protocol Developers
 * @dev Factory contract for the CoW AMM, an automated market maker based on the
 * concept of function-maximising AMMs.
 * The factory deploys new AMM and is responsible for managing deposits,
 * enabling/disabling trading and updating trade parameters.
 */
contract ConstantProductFactory {
    using SafeERC20 for IERC20;

    /**
     * @notice The settlement contract for CoW Protocol on this network.
     */
    ISettlement public immutable settler;

    /**
     * @notice For each AMM created by this contract, this mapping stores its
     * owner.
     */
    mapping(ConstantProduct => address) public owner;

    /**
     * @notice A CoW AMM has been enabled for trading.
     * @param amm The address of the AMM that can now trade on CoW Protocol.
     * @param owner The owner of the AMM.
     */
    event TradingEnabled(ConstantProduct indexed amm, address indexed owner);
    /**
     * @notice A CoW AMM stopped trading; no CoW Protocol orders can be settled
     * until trading is enabled again.
     * @param amm The address of the AMM that stops trading on CoW Protocol.
     * @param owner The owner of the AMM.
     */
    event TradingDisabled(ConstantProduct indexed amm, address indexed owner);

    /**
     * @notice This function is permissioned and can only be called by the
     * owner of the AMM that is involved in the transaction.
     * @param owner The owner of the AMM.
     */
    error OnlyOwnerCanCall(address owner);

    modifier onlyOwner(ConstantProduct amm) {
        if (owner[amm] != msg.sender) {
            revert OnlyOwnerCanCall(owner[amm]);
        }
        _;
    }

    /**
     * @param _settler The address of the GPv2Settlement contract.
     */
    constructor(ISettlement _settler) {
        settler = _settler;
    }

    /**
     * @notice Creates a new CoW AMM with the specified imput parameters.
     * @param token0 The address of the first token in the pair.
     * @param amount0 The initial amount of the first token in the pair.
     * @param token1 The address of the second token in the pair.
     * @param amount1 The initial amount of the second token in the pair.
     * @param minTradedToken0 The minimum amount of token0 before the AMM
     * attempts auto-rebalance.
     * @param priceOracle The address of the price oracle to use for the AMM.
     * @param priceOracleData The data to pass to the price oracle.
     * @param appData The app data to pass to the AMM.
     * @return amm The address of the newly deployed AMM.
     */
    function create(
        IERC20 token0,
        uint256 amount0,
        IERC20 token1,
        uint256 amount1,
        uint256 minTradedToken0,
        IPriceOracle priceOracle,
        bytes calldata priceOracleData,
        bytes32 appData
    ) external returns (ConstantProduct amm) {
        amm = new ConstantProduct(settler, token0, token1);
        owner[amm] = msg.sender;

        deposit(amm, amount0, amount1);

        ConstantProduct.TradingParams memory data = ConstantProduct.TradingParams({
            minTradedToken0: minTradedToken0,
            priceOracle: priceOracle,
            priceOracleData: priceOracleData,
            appData: appData
        });
        _enableTrading(amm, data);
    }

    /**
     * @notice Change the parameters used for trading on the specified AMM. Only
     * a single order per AMM can be valid at a time, meaning that any previous
     * order stops being tradeable.
     * @param amm The address of the AMM whose parameters to change.
     * @param minTradedToken0 The minimum amount of token0 before the AMM
     * attempts auto-rebalance.
     * @param priceOracle The address of the price oracle to use for the AMM.
     * @param priceOracleData The data to pass to the price oracle.
     * @param appData The app data to pass to the AMM.
     */
    function updateParameters(
        ConstantProduct amm,
        uint256 minTradedToken0,
        IPriceOracle priceOracle,
        bytes calldata priceOracleData,
        bytes32 appData
    ) external onlyOwner(amm) {
        ConstantProduct.TradingParams memory data = ConstantProduct.TradingParams({
            minTradedToken0: minTradedToken0,
            priceOracle: priceOracle,
            priceOracleData: priceOracleData,
            appData: appData
        });
        _disableTrading(amm);
        _enableTrading(amm, data);
    }

    /**
     * @notice Disable trading for an AMM managed by this contract.
     * @param amm The AMM for which to disable trading.
     */
    function disableTrading(ConstantProduct amm) external onlyOwner(amm) {
        _disableTrading(amm);
    }

    /**
     * @notice Take funds from the AMM and sends them to the owner.
     * @param amm the AMM whose funds to withdraw
     * @param amount0 amount of AMM's token0 to withdraw
     * @param amount1 amount of AMM's token1 to withdraw
     */
    function withdraw(ConstantProduct amm, uint256 amount0, uint256 amount1) external onlyOwner(amm) {
        amm.token0().safeTransferFrom(address(amm), msg.sender, amount0);
        amm.token1().safeTransferFrom(address(amm), msg.sender, amount1);
    }

    /**
     * @notice This function exists to let the watchtower off-chain service
     * automatically create AMM orders and post them on the orderbook. It
     * outputs an order for the input AMM together with a valid signature.
     * @dev Some parameters are unused as they refer to features of
     * ComposableCoW that aren't implemented in this contract. They are still
     * needed to let the watchtower interact with this contract in the same way
     * as ComposableCoW.
     * @param amm owner of the order.
     * @param params `ConditionalOrderParams` for the order; precisely, the
     * handler must be this contract, the salt can be any value, and the static
     * input must be the current trading parameters of the AMM.
     * @return order discrete order for submitting to CoW Protocol API
     * @return signature for submitting to CoW Protocol API
     */
    function getTradeableOrderWithSignature(
        ConstantProduct amm,
        IConditionalOrder.ConditionalOrderParams calldata params,
        bytes calldata, // offchainInput
        bytes32[] calldata // proof
    ) external view returns (GPv2Order.Data memory order, bytes memory signature) {
        // This contract mimics the interface of ConditionalCoW to talk to the
        // watchtower. In principle we'd still get a valid order if the handler
        // is set to any address. However, we create conditional orders on this
        // contract with this contract as the handler, so to make sure that the
        // user isn't trying to forward this order to the incorrect contract,
        // we revert with this error message.
        if (address(params.handler) != address(this)) {
            revert IConditionalOrder.OrderNotValid("can only handle own orders");
        }

        ConstantProduct.TradingParams memory tradingParams =
            abi.decode(params.staticInput, (ConstantProduct.TradingParams));

        // Check that `getTradeableOrderWithSignature` is being called with
        // parameters that are currently enabled for trading on the AMM.
        // If the parameters are different, this order can be deleted on the
        // watchtower.
        if (amm.hash(tradingParams) != amm.tradingParamsHash()) {
            revert IConditionalOrder.OrderNotValid("invalid trading parameters");
        }

        // Note: the salt in params is ignored.

        order = amm.getTradeableOrder(tradingParams);
        signature = abi.encode(order, tradingParams);
    }

    /**
     * @notice Deposit sender's funds into the the AMM contract, assuming that
     * the sender has approved this contract to spend both tokens.
     * @param amm the AMM where to send the funds
     * @param amount0 amount of AMM's token0 to deposit
     * @param amount1 amount of AMM's token1 to deposit
     */
    function deposit(ConstantProduct amm, uint256 amount0, uint256 amount1) public {
        amm.token0().safeTransferFrom(msg.sender, address(amm), amount0);
        amm.token1().safeTransferFrom(msg.sender, address(amm), amount1);
    }

    /**
     * @notice Enable trading for an existing AMM that is managed by this
     * contract.
     * @param amm The AMM for which to enable trading.
     * @param tradingParams The parameters used by the CoW AMM to create the
     * order.
     */
    function _enableTrading(ConstantProduct amm, ConstantProduct.TradingParams memory tradingParams) internal {
        amm.enableTrading(tradingParams);
        emit TradingEnabled(amm, msg.sender);
        // The salt is unused by this contract. However, external tools (for
        // example the watch tower) may expect that the salt doesn't repeat.
        // This cannot be achieved without extra state or bubbling up the nonce
        // parameter to the caller.
        // We assume that external tools are able to handle the case where the
        // exact same order is created two times in the same block for the
        // exact same parameters, AMM address, and owner.
        // Note that there can be at most one active order per AMM by
        // construction, and a repeating salt means that the order was created,
        // cancelled, and then recreated with the same parameters on the same
        // block.
        bytes32 salt = bytes32(bytes20(msg.sender)) | bytes32(block.timestamp);
        // The following event will be pickd up by the watchtower offchain
        // service, which is responsible for automatically posting CoW AMM
        // orders on the CoW Protocol orderbook.
        emit ComposableCoW.ConditionalOrderCreated(
            address(amm),
            IConditionalOrder.ConditionalOrderParams(IConditionalOrder(address(this)), salt, abi.encode(tradingParams))
        );
    }

    /**
     * @notice Disable trading for an AMM managed by this contract.
     * @param amm The AMM for which to disable trading.
     */
    function _disableTrading(ConstantProduct amm) internal {
        amm.disableTrading();
        emit TradingDisabled(amm, msg.sender);
    }
}
