// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {DeployUniswapV2PriceOracle, UniswapV2PriceOracle} from "./single-deployment/UniswapV2PriceOracle.s.sol";
import {DeployConstantProductFactory, ConstantProductFactory} from "./single-deployment/ConstantProductFactory.s.sol";
import {
    DeployBalancerWeightedPoolPriceOracle,
    BalancerWeightedPoolPriceOracle
} from "./single-deployment/BalancerWeightedPoolPriceOracle.s.sol";
import {DeployChainlinkPriceOracle, ChainlinkPriceOracle} from "./single-deployment/ChainlinkPriceOracle.s.sol";

contract DeployAllContracts is
    DeployConstantProductFactory,
    DeployUniswapV2PriceOracle,
    DeployBalancerWeightedPoolPriceOracle,
    DeployChainlinkPriceOracle
{
    function run()
        public
        override(
            DeployConstantProductFactory,
            DeployUniswapV2PriceOracle,
            DeployBalancerWeightedPoolPriceOracle,
            DeployChainlinkPriceOracle
        )
    {
        deployAll();
    }

    function deployAll()
        public
        returns (
            ConstantProductFactory constantProductFactory,
            UniswapV2PriceOracle uniswapV2PriceOracle,
            BalancerWeightedPoolPriceOracle balancerWeightedPoolPriceOracle,
            ChainlinkPriceOracle chainlinkPriceOracle
        )
    {
        constantProductFactory = deployConstantProductFactory();
        uniswapV2PriceOracle = deployUniswapV2PriceOracle();
        balancerWeightedPoolPriceOracle = deployBalancerWeightedPoolPriceOracle();
        chainlinkPriceOracle = deployChainlinkPriceOracle();
    }
}
