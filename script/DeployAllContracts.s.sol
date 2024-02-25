// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {DeployUniswapV2PriceOracle, UniswapV2PriceOracle} from "./single-deployment/UniswapV2PriceOracle.s.sol";
import {DeployConstantProduct, ConstantProduct} from "./single-deployment/ConstantProduct.s.sol";
import {
    DeployBalancerWeightedPoolPriceOracle,
    BalancerWeightedPoolPriceOracle
} from "./single-deployment/BalancerWeightedPoolPriceOracle.s.sol";
import {DeployCowAmmModule, CowAmmModule} from "./single-deployment/CowAmmModule.s.sol";

contract DeployAllContracts is
    DeployConstantProduct,
    DeployUniswapV2PriceOracle,
    DeployBalancerWeightedPoolPriceOracle,
    DeployCowAmmModule
{
    function run()
        public
        override(
            DeployConstantProduct, DeployUniswapV2PriceOracle, DeployBalancerWeightedPoolPriceOracle, DeployCowAmmModule
        )
    {
        deployAll();
    }

    function deployAll()
        public
        returns (
            ConstantProduct constantProduct,
            UniswapV2PriceOracle uniswapV2PriceOracle,
            BalancerWeightedPoolPriceOracle balancerWeightedPoolPriceOracle,
            CowAmmModule cowAmmModule
        )
    {
        constantProduct = deployConstantProduct();
        uniswapV2PriceOracle = deployUniswapV2PriceOracle();
        balancerWeightedPoolPriceOracle = deployBalancerWeightedPoolPriceOracle();
        cowAmmModule = deployCowAmmModule(address(constantProduct));
    }
}
