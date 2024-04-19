// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IConditionalOrder} from "lib/composable-cow/src/ComposableCoW.sol";
import {SafeERC20} from "lib/composable-cow/lib/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ConstantProduct, IERC20, ISettlement, GPv2Order} from "./ConstantProduct.sol";

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
}
