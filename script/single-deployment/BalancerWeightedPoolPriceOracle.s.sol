// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script, console} from "forge-std/Script.sol";

import {BalancerWeightedPoolPriceOracle, IVault} from "src/oracles/BalancerWeightedPoolPriceOracle.sol";

contract DeployBalancerWeightedPoolPriceOracle is Script {
    string constant balancerVaultEnv = "BALANCER_VAULT";
    IVault internal vault;

    constructor() {
        try vm.envAddress(balancerVaultEnv) returns (address vault_) {
            vault = IVault(vault_);
        } catch {
            vault = defaultBalancerVault();
        }
        console.log("Balancer vault at %s.", address(vault));
        // We assume that if there's code at that address, then it's a Balancer
        // vault deployment. This isn't guaranteed because they don't use
        // deterministic addresses and in theory there could be any contract
        // there.
        require(address(vault).code.length > 0, "no code at expected Balancer vault");
    }

    function run() public virtual {
        deployBalancerWeightedPoolPriceOracle();
    }

    function deployBalancerWeightedPoolPriceOracle() internal returns (BalancerWeightedPoolPriceOracle) {
        vm.broadcast();
        return new BalancerWeightedPoolPriceOracle(vault);
    }

    function defaultBalancerVault() internal pure returns (IVault) {
        // Balancer uses the same address on each supported chain until now:
        // https://docs.balancer.fi/reference/contracts/deployment-addresses/mainnet.html
        // Chains: Arbitrum, Avalanche, Base, Gnosis, Goerli, Mainnet, Optimism,
        // Polygon, Sepolia, Zkevm
        return IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    }
}
