// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC1271} from "lib/openzeppelin/contracts/interfaces/IERC1271.sol";
import {SafeERC20} from "lib/openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "lib/openzeppelin/contracts/utils/math/Math.sol";
import {ConditionalOrdersUtilsLib as Utils} from "lib/composable-cow/src/types/ConditionalOrdersUtilsLib.sol";
import {IConditionalOrder, GPv2Order} from "lib/composable-cow/src/BaseConditionalOrder.sol";

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
contract ConstantProduct is IERC1271 {
    using SafeERC20 for IERC20;
    using GPv2Order for GPv2Order.Data;

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
     * @notice The transient storage slot specified in this variable stores the
     * value of the order commitment, that is, the only order hash that can be
     * validated by calling `isValidSignature`.
     * The hash corresponding to the constant `EMPTY_COMMITMENT` has special
     * semantics, discussed in the related documentation.
     * @dev This value is:
     * uint256(keccak256("CoWAMM.ConstantProduct.commitment")) - 1
     */
    uint256 public constant COMMITMENT_SLOT = 0x6c3c90245457060f6517787b2c4b8cf500ca889d2304af02043bd5b513e3b593;
    /**
     * @dev {"appCode":"Testing CoW AMM: abridged standalone","version":"1.1.0"}
     */
    bytes32 public constant APP_DATA = 0x555ea39564bc0bdb86c923141da12754e14676ae1fd8fcf6b26ae04abdfa0298;

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
     * Is trading enabled?
     */
    bool public tradingEnabled = false;

    /**
     * Emitted when the manager disables all trades by the AMM. Existing open
     * order will not be tradeable. Note that the AMM could resume trading with
     * different parameters at a later point.
     */
    event TradingDisabled();
    /**
     * Emitted when the manager enables the AMM to trade on CoW Protocol.
     */
    event TradingEnabled();

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
     * Protocol whose hash doesn't match the one that has been committed to.
     */
    error OrderDoesNotMatchCommitmentHash();
    /**
     * @notice If an AMM order is settled and the AMM committment is set to
     * empty, then that order must match the output of `getTradeableOrder`.
     * This error is thrown when some of the parameters don't match the expected
     * ones.
     */
    error OrderDoesNotMatchDefaultTradeableOrder();
    /**
     * @notice On signature verification, the hash of the order supplied as part
     * of the signature does not match the provided message hash.
     * This usually means that the verification function is being provided a
     * signature that belongs to a different order.
     */
    error OrderDoesNotMatchMessageHash();

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
     */
    function enableTrading() external onlyManager {
        tradingEnabled = true;
        emit TradingEnabled();
    }

    /**
     * @notice Disable any form of trading on CoW Protocol by this AMM.
     */
    function disableTrading() external onlyManager {
        tradingEnabled = false;
        emit TradingDisabled();
    }

    /**
     * @notice Restricts a specific AMM to being able to trade only the order
     * with the specified hash.
     * @dev The commitment is used to enforce that exactly one AMM order is
     * valid when a CoW Protocol batch is settled.
     * @param orderHash the order hash that will be enforced by the order
     * verification function.
     */
    function commit(bytes32 orderHash) external {
        if (msg.sender != address(solutionSettler)) {
            revert CommitOutsideOfSettlement();
        }
        assembly ("memory-safe") {
            tstore(COMMITMENT_SLOT, orderHash)
        }
    }

    /**
     * @inheritdoc IERC1271
     */
    function isValidSignature(bytes32 _hash, bytes calldata signature) external view returns (bytes4) {
        GPv2Order.Data memory order = abi.decode(signature, (GPv2Order.Data));

        bytes32 orderHash = order.hash(solutionSettlerDomainSeparator);
        if (orderHash != _hash) {
            revert OrderDoesNotMatchMessageHash();
        }

        if (orderHash != commitment()) {
            revert OrderDoesNotMatchCommitmentHash();
        }

        verify(order);

        // A signature is valid according to EIP-1271 if this function returns
        // its selector as the so-called "magic value".
        return this.isValidSignature.selector;
    }

    /**
     * @notice This function checks that the input order is admissible for the
     * constant-product curve for the given trading parameters.
     * @param order `GPv2Order.Data` of a discrete order to be verified.
     */
    function verify(GPv2Order.Data memory order) public view {
        IERC20 sellToken = token0;
        IERC20 buyToken = token1;
        if (order.sellToken != sellToken) {
            if (order.sellToken != buyToken) {
                revert IConditionalOrder.OrderNotValid("invalid sell token");
            }
            (sellToken, buyToken) = (buyToken, sellToken);
        }
        uint256 sellReserve = sellToken.balanceOf(address(this));
        uint256 buyReserve = buyToken.balanceOf(address(this));

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
        if (order.appData != APP_DATA) {
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

    function commitment() public view returns (bytes32 value) {
        assembly ("memory-safe") {
            value := tload(COMMITMENT_SLOT)
        }
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
}
