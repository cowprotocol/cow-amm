// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

abstract contract BalancerSetUp is Test {
    function setUpBalancerVault() internal {
        vm.etch(0xBA12222222228d8Ba445958a75a0704d566BF2C8, hex"1337");
    }
}
