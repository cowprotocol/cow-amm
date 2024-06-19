// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {ComposableCoW, IConditionalOrder} from "lib/composable-cow/src/ComposableCoW.sol";
import {SafeERC20} from "lib/openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICOWAMMPoolFactory} from "./interfaces/ICOWAMMPoolFactory.sol";
import {ConstantProduct, IERC20, ISettlement, GPv2Order, IPriceOracle} from "./ConstantProduct.sol";

/**
 * @title CoW AMM Factory
 * @author CoW Protocol Developers
 * @dev Factory contract for the CoW AMM, an automated market maker based on the
 * concept of function-maximising AMMs.
 * The factory deploys new AMM and is responsible for managing deposits,
 * enabling/disabling trading and updating trade parameters.
 */
contract ConstantProductFactory is ICOWAMMPoolFactory {
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
     * @notice A CoW AMM has been created. The emitted AMM parameters are
     * immutable for the new AMM.
     * @param amm The address of the AMM that can now trade on CoW Protocol.
     * @param owner The owner of the AMM.
     * @param token0 The first token traded by the AMM.
     * @param token1 The second token traded by the AMM.
     */
    event Deployed(ConstantProduct indexed amm, address indexed owner, IERC20 token0, IERC20 token1);
    /**
     * @notice A CoW AMM stopped trading; no CoW Protocol orders can be settled
     * until trading is enabled again.
     * @param amm The address of the AMM that stops trading on CoW Protocol.
     */
    event TradingDisabled(ConstantProduct indexed amm);

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
     * @return amm The address of the newly deployed AMM.
     */
    function create(IERC20 token0, uint256 amount0, IERC20 token1, uint256 amount1)
        external
        returns (ConstantProduct amm)
    {
        address ammOwner = msg.sender;
        amm = new ConstantProduct{salt: salt(ammOwner)}(settler, token0, token1);
        emit Deployed(amm, ammOwner, token0, token1);
        emit COWAMMPoolCreated(address(amm));
        owner[amm] = ammOwner;

        deposit(amm, amount0, amount1);

        _enableTrading(amm);
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
     * @notice Computes the determinisitic address of a CoW AMM deployment.
     * @param ammOwner The (expected) owner of the AMM.
     * @param token0 The address of the first token traded by the AMM.
     * @param token1 The address of the second token traded by the AMM.
     * @return The deterministic address at which this contract deploys a CoW
     * AMM for the specified input parameters.
     */
    function ammDeterministicAddress(address ammOwner, IERC20 token0, IERC20 token1) external view returns (address) {
        // https://eips.ethereum.org/EIPS/eip-1014#specification
        bytes32 create2Hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt(ammOwner),
                keccak256(
                    bytes.concat(
                        type(ConstantProduct).creationCode,
                        // Input parameters are appended at the end of the
                        // creation bytecode.
                        abi.encode(settler, token0, token1)
                    )
                )
            )
        );

        // Take the last 20 bytes of the hash as the address.
        return address(uint160(uint256(create2Hash)));
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
     * order.
     */
    function _enableTrading(ConstantProduct amm) internal {
        amm.enableTrading();
        // The salt is unused by this contract. External tools (for example the
        // watch tower) may expect that the salt doesn't repeat. However, there
        // can be at most one valid order per AMM at a time, and any conflicting
        // order would have been invalidated before a conflict can occur.
        bytes32 conditionalOrderSalt = bytes32(0);
        // The following event will be pickd up by the watchtower offchain
        // service, which is responsible for automatically posting CoW AMM
        // orders on the CoW Protocol orderbook.
        emit ComposableCoW.ConditionalOrderCreated(
            address(amm),
            IConditionalOrder.ConditionalOrderParams(IConditionalOrder(address(this)), conditionalOrderSalt, hex"")
        );
    }

    /**
     * @notice Disable trading for an AMM managed by this contract.
     * @param amm The AMM for which to disable trading.
     */
    function _disableTrading(ConstantProduct amm) internal {
        amm.disableTrading();
        emit TradingDisabled(amm);
    }

    /**
     * @notice Salt parameter used for deterministic AMM deployments.
     * @param ammOwner The (expected) owner of the AMM.
     * @return The salt to use for deploying the AMM with CREATE2.
     */
    function salt(address ammOwner) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(ammOwner)));
    }
}
