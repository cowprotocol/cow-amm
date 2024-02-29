// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {DeployCowAmmModule} from "script/single-deployment/CowAmmModule.s.sol";
import {Utils} from "test/libraries/Utils.sol";

import {CowProtocolSetUp} from "./cow-protocol/CowProtocolSetUp.sol";
import {SafeSetUp} from "./safe/SafeSetUp.sol";

address constant ETCHED_HANDLER = address(bytes20(keccak256("predeployed-handler")));

contract DeployCowAmmModuleTest is Test, CowProtocolSetUp, SafeSetUp {
    DeployCowAmmModule script;
    DeployCowAmmModuleTestDeployer goodScript;

    function setUp() public {
        setUpSettlementContract();
        setUpComposableCowContract();
        setUpSafeExtensibleFallbackHandler();

        vm.etch(ETCHED_HANDLER, hex"1337");

        script = new DeployCowAmmModule();
        goodScript = new DeployCowAmmModuleTestDeployer();
    }

    function testRevertsIfHandlerNotSpecified() public {
        vm.expectRevert();
        script.run();
    }

    function testDoesNotRevert() public {
        goodScript.run();
    }
}

contract DeployCowAmmModuleTestDeployer is DeployCowAmmModule {
    constructor() DeployCowAmmModule() {
        handler = ETCHED_HANDLER;
    }
}
