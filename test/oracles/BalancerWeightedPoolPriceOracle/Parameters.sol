// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";

import {Utils} from "test/libraries/Utils.sol";
import {BalancerWeightedPoolPriceOracle, IVault} from "src/oracles/BalancerWeightedPoolPriceOracle.sol";

contract BalancerWeightedPoolPriceOracleTest is Test {
    IVault internal balancerVault;
    BalancerWeightedPoolPriceOracle internal oracle;

    function setUp() public {
        oracle = new BalancerWeightedPoolPriceOracle(balancerVault);
    }

    function testVaultAddress() public {
        assertEq(address(oracle.vault()), address(balancerVault));
    }
}
