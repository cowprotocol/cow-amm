// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {DeployChainlinkPriceOracle} from "script/single-deployment/ChainlinkPriceOracle.s.sol";

contract DeployChainlinkPriceOracleTest is Test {
    DeployChainlinkPriceOracle script;

    function setUp() public {
        script = new DeployChainlinkPriceOracle();
    }

    function testDoesNotRevert() public {
        script.run();
    }
}
