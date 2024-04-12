// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {console} from "forge-std/Script.sol";

import {ConstantProduct, IERC20} from "src/ConstantProduct.sol";

import {EnvReader} from "script/libraries/EnvReader.sol";
import {Utils} from "script/libraries/Utils.sol";

contract DeployConstantProduct is EnvReader, Utils {
    constructor() {
        solutionSettler = addressEnvOrDefault("SETTLEMENT_CONTRACT", DEFAULT_SETTLEMENT_CONTRACT);
        console.log("Settlement contract at %s.", solutionSettler);
        assertHasCode(solutionSettler, "no code at expected settlement contract");
    }

    function run() public virtual {
        deployConstantProduct();
    }

    function deployConstantProduct() internal returns (ConstantProduct) {
        vm.broadcast();
        return new ConstantProduct(solutionSettler, IERC20(vm.envAddress("TOKEN_0")), IERC20(vm.envAddress("TOKEN_1")));
    }
}
