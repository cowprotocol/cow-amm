// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {TestAccount} from "lib/composable-cow/test/ComposableCoW.base.t.sol";

library TestAccountHelper {
    function toAddresses(TestAccount[] memory accounts) internal pure returns (address[] memory addresses) {
        addresses = new address[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            addresses[i] = accounts[i].addr;
        }
    }
}
