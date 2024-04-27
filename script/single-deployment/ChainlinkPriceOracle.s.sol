// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";

import {ChainlinkPriceOracle} from "src/oracles/ChainlinkPriceOracle.sol";

contract DeployChainlinkPriceOracle is Script {
    function run() public virtual {
        deployChainlinkPriceOracle();
    }

    function deployChainlinkPriceOracle() internal returns (ChainlinkPriceOracle) {
        vm.broadcast();
        return new ChainlinkPriceOracle();
    }
}
