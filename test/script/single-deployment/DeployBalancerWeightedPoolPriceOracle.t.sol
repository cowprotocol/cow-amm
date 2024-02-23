// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {DeployBalancerWeightedPoolPriceOracle} from "script/single-deployment/BalancerWeightedPoolPriceOracle.s.sol";

import {BalancerSetUp} from "./balancer/BalancerSetUp.sol";

contract DeployBalancerWeightedPoolPriceOracleTest is Test, BalancerSetUp {
    DeployBalancerWeightedPoolPriceOracle script;

    function setUp() public {
        setUpBalancerVault();
        script = new DeployBalancerWeightedPoolPriceOracle();
    }

    function testDoesNotRevert() public {
        script.run();
    }
}
