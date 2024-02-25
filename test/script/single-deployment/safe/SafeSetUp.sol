// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";

abstract contract SafeSetUp is Test {
    function setUpSafeExtensibleFallbackHandler() internal {
        vm.etch(0x2f55e8b20D0B9FEFA187AA7d00B6Cbe563605bF5, hex"1337");
    }
}
