// SPDX-License-Identifier: LGPL-3.0-only

// Vendored from Safe Global contracts with minor modifications:
// - Removed all functions except `execTransactionFromModuleReturnData`
// - Used naming convention for interface of `ISafe`
// - Minor edits to dev comments removing title
// <https://github.com/safe-global/safe-smart-account/blob/914d0f8fab0e8f73ef79581f6fbce86e34b049c3/contracts/interfaces/IModuleManager.sol>

pragma solidity >=0.7.0 <0.9.0;

import {Enum} from "safe/contracts/common/Enum.sol";

/**
 * @notice Modules are extensions with unlimited access to a Safe that can be added to a Safe by its owners.
 *            ⚠️ WARNING: Modules are a security risk since they can execute arbitrary transactions, 
 *            so only trusted and audited modules should be added to a Safe. A malicious module can
 *            completely takeover a Safe.
 * @author @safe-global/safe-protocol
 */
interface ISafe {
    /**
     * @notice Execute `operation` (0: Call, 1: DelegateCall) to `to` with `value` (Native Token) and return data
     * @param to Destination address of module transaction.
     * @param value Ether value of module transaction.
     * @param data Data payload of module transaction.
     * @param operation Operation type of module transaction.
     * @return success Boolean flag indicating if the call succeeded.
     * @return returnData Data returned by the call.
     */
    function execTransactionFromModuleReturnData(address to, uint256 value, bytes memory data, Enum.Operation operation)
        external
        returns (bool success, bytes memory returnData);
}
