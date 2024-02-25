// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {CowAmmModuleTestHarness, CowAmmModule, ConstantProduct} from "./CowAmmModuleTestHarness.sol";
import {FallbackManager} from "lib/composable-cow/lib/safe/contracts/Safe.sol";

abstract contract CloseAmmTest is CowAmmModuleTestHarness {

    function testCloseAmmWhenOneExists() public {
        setUpDefaultCowAmm();

        bytes32 previousOrderHash = cowAmmModule.activeOrders(safe);

        vm.prank(address(safe));

        vm.expectEmit(true, true, true, false);
        emit CowAmmModule.CowAmmClosed(safe, previousOrderHash);
        cowAmmModule.closeAmm();

        assertEq(cowAmmModule.activeOrders(safe), bytes32(0));
    }

    function testCloseAmmWhenNoneExists() public {
        setUpDefaultSafe();

        assertTrue(cowAmmModule.activeOrders(safe) == bytes32(0));

        vm.prank(address(safe));
        cowAmmModule.closeAmm();

        assertEq(cowAmmModule.activeOrders(safe), bytes32(0));
    }
}
