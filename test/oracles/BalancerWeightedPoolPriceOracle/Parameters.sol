// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

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
