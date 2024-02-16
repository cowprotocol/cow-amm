// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";

abstract contract CowProtocolSetUp is Test {
    function setUpSettlementContract() internal {
        vm.etch(0x9008D19f58AAbD9eD0D60971565AA8510560ab41, hex"1337");
    }
}
