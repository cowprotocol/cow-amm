// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {console} from "forge-std/Script.sol";

import {ComposableCoW} from "lib/composable-cow/src/ComposableCoW.sol";
import {GPv2Settlement} from "lib/composable-cow/lib/cowprotocol/src/contracts/GPv2Settlement.sol";
import {ExtensibleFallbackHandler} from "lib/composable-cow/lib/safe/contracts/handler/ExtensibleFallbackHandler.sol";
import {IConditionalOrder} from "lib/composable-cow/src/BaseConditionalOrder.sol";

import {CowAmmModule, IERC20} from "src/CowAmmModule.sol";
import {EnvReader} from "script/libraries/EnvReader.sol";
import {Utils} from "script/libraries/Utils.sol";

contract DeployCowAmmModule is EnvReader, Utils {
    address internal handler;

    constructor() {
        solutionSettler = addressEnvOrDefault("SETTLEMENT_CONTRACT", DEFAULT_SETTLEMENT_CONTRACT);
        extensibleFallbackHandler =
            addressEnvOrDefault("EXTENSIBLE_FALLBACK_HANDLER_CONTRACT", DEFAULT_EXTENSIBLE_FALLBACK_HANDLER_CONTRACT);
        composableCow = addressEnvOrDefault("COMPOSABLE_COW_CONTRACT", DEFAULT_COMPOSABLE_COW_CONTRACT);

        // Special case as the contract address might be determined at run time.
        handler = addressEnvOrDefault("CONSTANT_PRODUCT_CONTRACT", address(0));

        console.log("Settlement contract at %s.", solutionSettler);
        console.log("ExtensibleFallbackHandler contract at %s.", extensibleFallbackHandler);
        console.log("ComposableCoW contract at %s.", composableCow);

        assertHasCode(solutionSettler, "no code at expected solution settler contract");
        assertHasCode(extensibleFallbackHandler, "no code at expected extensible fallback handler contract");
        assertHasCode(composableCow, "no code at expected composable cow contract");

        // Special case: if the constant product contract is not provided, we assume
        // that this script is being called from DeployAllContracts and that the
        // constant product contract will be deployed by it.
        if (handler != address(0)) {
            console.log("handler contract at %s.", handler);
            assertHasCode(handler, "no code at expected handler contract");
        }
    }

    function run() public virtual {
        deployCowAmmModule(handler);
    }

    function deployCowAmmModule(address _handler) internal returns (CowAmmModule) {
        if (_handler == address(0)) {
            console.log("No constant product contract provided!");
            revert();
        }
        console.log("handler contract at %s.", _handler);
        assertHasCode(_handler, "no code at expected handler contract");

        vm.broadcast();
        return new CowAmmModule(
            GPv2Settlement(payable(solutionSettler)),
            ExtensibleFallbackHandler(extensibleFallbackHandler),
            ComposableCoW(composableCow),
            IConditionalOrder(_handler),
            IERC20(vm.envAddress("TOKEN_0")),
            IERC20(vm.envAddress("TOKEN_1"))
        );
    }
}
