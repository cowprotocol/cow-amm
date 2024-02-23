// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {DeployUniswapV2PriceOracle, UniswapV2PriceOracle} from "./single-deployment/UniswapV2PriceOracle.s.sol";
import {DeployConstantProduct, ConstantProduct} from "./single-deployment/ConstantProduct.s.sol";
import {
    DeployBalancerWeightedPoolPriceOracle,
    BalancerWeightedPoolPriceOracle
} from "./single-deployment/BalancerWeightedPoolPriceOracle.s.sol";

contract DeployAllContracts is
    DeployConstantProduct,
    DeployUniswapV2PriceOracle,
    DeployBalancerWeightedPoolPriceOracle
{
    function run()
        public
        override(DeployConstantProduct, DeployUniswapV2PriceOracle, DeployBalancerWeightedPoolPriceOracle)
    {
        deployAll();
    }

    function deployAll()
        public
        returns (
            ConstantProduct constantProduct,
            UniswapV2PriceOracle uniswapV2PriceOracle,
            BalancerWeightedPoolPriceOracle balancerWeightedPoolPriceOracle
        )
    {
        constantProduct = deployConstantProduct();
        uniswapV2PriceOracle = deployUniswapV2PriceOracle();
        balancerWeightedPoolPriceOracle = deployBalancerWeightedPoolPriceOracle();
    }
}
