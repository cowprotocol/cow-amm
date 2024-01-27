// SPDX-License-Identifier: MIT

// Vendored from OpenZeppelin contracts with minor modifications:
// - Removed all functions except `safeTransfer`, `safeTransferFrom` and `_callOptionalReturn`
// - Functions modified to accept an `ISafe` and `IERC20` as the first two arguments
//   which is the Safe used to execute the transaction and the token being transferred.
//   For executing the transaction, uses the `functionCall` function from SafeModuleAddress.sol.
// - Added imports for Safe related contracts.
// - Minor edits to dev comments removing `SafeERC20` references.
// <https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/token/ERC20/utils/SafeERC20.sol>

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.20;

import {IERC20} from "lib/composable-cow/lib/@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeModuleAddress} from "./SafeModuleAddress.sol";
import {ISafe, Enum} from "../interfaces/ISafe.sol";

/**
 * @title SafeModuleSafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 */
library SafeModuleSafeERC20 {
    /**
     * @dev An operation with an ERC20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(ISafe safe, IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(safe, token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(ISafe safe, IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(safe, token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(ISafe safe, IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {SafeModuleAddress-functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = SafeModuleAddress.functionCall(safe, address(token), data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20FailedOperation(address(token));
        }
    }
}
