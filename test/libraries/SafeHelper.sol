// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {SafeLib, Safe, Enum as SafeEnum, TestAccount} from "lib/composable-cow/test/ComposableCoW.base.t.sol";
import {SafeProxyFactory} from "lib/composable-cow/lib/safe/contracts/proxies/SafeProxyFactory.sol";

import {TestAccountHelper} from "./TestAccountHelper.sol";

// This library exists as a wrapper to handle Safe Multisig more easily.
// If possible, SafeHelper would extend SafeLib.
// Ideally, this library should be combined with SafeLib and a few features
// should be added. Most notably, `execCall` should revert when the safe
// transaction reverts.
library SafeHelper {
    using TestAccountHelper for TestAccount[];

    function execCall(Safe safe, address to, uint256 value, bytes memory data, TestAccount[] memory owners) internal {
        SafeLib.execute(safe, to, value, data, SafeEnum.Operation.Call, owners);
    }

    function execCall(Safe safe, address to, bytes memory data, TestAccount[] memory owners) internal {
        execCall(safe, to, 0, data, owners);
    }

    function createSafe(
        SafeProxyFactory factory,
        Safe singleton,
        TestAccount[] memory owners,
        uint256 threshold,
        address handler
    ) internal returns (Safe safe) {
        uint256 uniqueSalt =
            uint256(keccak256(abi.encode("Test Safe Multisig from SafeHelper library", msg.data, block.number)));
        safe =
            Safe(payable(SafeLib.createSafe(factory, singleton, owners.toAddresses(), threshold, handler, uniqueSalt)));
    }
}
