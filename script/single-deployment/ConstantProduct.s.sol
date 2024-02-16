// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script, console} from "forge-std/Script.sol";

import {Utils} from "../libraries/Utils.sol";

import {ConstantProduct} from "src/ConstantProduct.sol";

contract DeployConstantProduct is Script, Utils {
    address internal constant DEFAULT_SETTLEMENT_CONTRACT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal solutionSettler;

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
        return new ConstantProduct(solutionSettler);
    }
}
