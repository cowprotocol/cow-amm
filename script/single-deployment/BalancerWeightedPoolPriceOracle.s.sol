// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script, console} from "forge-std/Script.sol";

import {Utils} from "../libraries/Utils.sol";

import {BalancerWeightedPoolPriceOracle, IVault} from "src/oracles/BalancerWeightedPoolPriceOracle.sol";

contract DeployBalancerWeightedPoolPriceOracle is Script, Utils {
    // Balancer uses the same address on each supported chain until now:
    // https://docs.balancer.fi/reference/contracts/deployment-addresses/mainnet.html
    // Chains: Arbitrum, Avalanche, Base, Gnosis, Goerli, Mainnet, Optimism,
    // Polygon, Sepolia, Zkevm
    address internal constant DEFAULT_BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    IVault internal vault;

    constructor() {
        address vaultAddress = addressEnvOrDefault("BALANCER_VAULT", DEFAULT_BALANCER_VAULT);
        console.log("Balancer vault at %s.", vaultAddress);
        // We assume that if there's code at that address, then it's a Balancer
        // vault deployment. This isn't guaranteed because they don't use
        // deterministic addresses and in theory there could be any contract
        // there.
        assertHasCode(vaultAddress, "no code at expected Balancer vault");
        vault = IVault(vaultAddress);
    }

    function run() public virtual {
        deployBalancerWeightedPoolPriceOracle();
    }

    function deployBalancerWeightedPoolPriceOracle() internal returns (BalancerWeightedPoolPriceOracle) {
        vm.broadcast();
        return new BalancerWeightedPoolPriceOracle(vault);
    }
}
