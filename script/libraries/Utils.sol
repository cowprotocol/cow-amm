// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";

abstract contract Utils is Script {
    address internal constant DEFAULT_SETTLEMENT_CONTRACT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant DEFAULT_EXTENSIBLE_FALLBACK_HANDLER_CONTRACT = 0x2f55e8b20D0B9FEFA187AA7d00B6Cbe563605bF5;
    address internal constant DEFAULT_COMPOSABLE_COW_CONTRACT = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;

    address internal solutionSettler;
    address internal extensibleFallbackHandler;
    address internal composableCow;

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
