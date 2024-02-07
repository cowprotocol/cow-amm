// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";

import {UniswapV2PriceOracle} from "src/oracles/UniswapV2PriceOracle.sol";

contract DeployUniswapV2PriceOracle is Script {
    function run() public virtual {
        deployUniswapV2PriceOracle();
    }

    function deployUniswapV2PriceOracle() internal returns (UniswapV2PriceOracle) {
        vm.broadcast();
        return new UniswapV2PriceOracle();
    }
}
