// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {CowAmmModuleTestHarness, CowAmmModule, ConstantProduct, ComposableCoW} from "./CowAmmModuleTestHarness.sol";
import {FallbackManager} from "lib/composable-cow/lib/safe/contracts/Safe.sol";

abstract contract CloseAmmTest is CowAmmModuleTestHarness {
    function testCloseAmmWhenOneExists() public {
        setUpDefaultCowAmm();

        bytes32 previousOrderHash = cowAmmModule.activeOrders(safe);
        require(cowAmmModule.activeOrders(safe) != bytes32(0), "no order created in setup");

        vm.prank(address(safe));

        vm.expectEmit();
        emit CowAmmModule.CowAmmClosed(safe, previousOrderHash);
        cowAmmModule.closeAmm();

        assertEq(cowAmmModule.activeOrders(safe), bytes32(0));
        assertFalse(composableCow.singleOrders(address(safe), previousOrderHash));
    }

    function testCloseAmmWhenNoneExists() public {
        setUpDefaultSafe();

        assertEq(cowAmmModule.activeOrders(safe), bytes32(0));

        vm.mockCallRevert(
            address(composableCow),
            abi.encodeWithSelector(ComposableCoW.remove.selector),
            abi.encode("called remove when shouldn't have")
        );
        vm.prank(address(safe));
        cowAmmModule.closeAmm();

        assertEq(cowAmmModule.activeOrders(safe), bytes32(0));
    }
}
