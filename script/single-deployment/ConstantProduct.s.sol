// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";

import {ConstantProduct} from "src/ConstantProduct.sol";

contract DeployConstantProduct is Script {
    function run() public virtual {
        deployConstantProduct();
    }

    function deployConstantProduct() internal returns (ConstantProduct) {
        vm.broadcast();
        return new ConstantProduct();
    }
}
