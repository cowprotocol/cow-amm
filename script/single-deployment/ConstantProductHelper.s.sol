// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

import {ConstantProductHelper} from "src/ConstantProductHelper.sol";

contract DeployConstantProductHelper is Script {
    function run() public virtual {
        deployConstantProductHelper();
    }

    function deployConstantProductHelper() internal returns (ConstantProductHelper) {
        vm.broadcast();
        return new ConstantProductHelper();
    }
}
