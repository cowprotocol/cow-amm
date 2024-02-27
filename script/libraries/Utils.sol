// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";

abstract contract Utils is Script {
    function assertHasCode(address a, string memory context) internal view {
        require(a.code.length > 0, context);
    }
}
