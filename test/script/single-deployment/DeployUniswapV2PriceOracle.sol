// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {DeployUniswapV2PriceOracle} from "script/single-deployment/UniswapV2PriceOracle.s.sol";

contract DeployUniswapV2PriceOracleTest is Test {
    DeployUniswapV2PriceOracle script;

    function setUp() public {
        script = new DeployUniswapV2PriceOracle();
    }

    function testDoesNotRevert() public {
        script.run();
    }
}
