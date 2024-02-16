// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";

abstract contract Utils is Script {
    function addressEnvOrDefault(string memory envName, address defaultAddr) internal view returns (address) {
        try vm.envAddress(envName) returns (address env) {
            return env;
        } catch {
            return defaultAddr;
        }
    }

    function assertHasCode(address a, string memory context) internal view {
        require(a.code.length > 0, context);
    }
}
