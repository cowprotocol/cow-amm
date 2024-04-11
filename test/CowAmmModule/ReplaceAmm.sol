// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {CowAmmModuleTestHarness, CowAmmModule, ConstantProduct} from "./CowAmmModuleTestHarness.sol";
import {FallbackManager} from "lib/composable-cow/lib/safe/contracts/Safe.sol";

abstract contract ReplaceAmmTest is CowAmmModuleTestHarness {
    function testReplaceAmmWhenOneExists() public {
        setUpDefaultCowAmm();

        bytes32 previousOrderHash = cowAmmModule.activeOrders(safe);
        require(previousOrderHash != bytes32(0), "no order created in setup");

        ConstantProduct.Data memory ammData = getDefaultData();
        ammData.minTradedToken0 = 1;

        bytes32 newPreCalculatedOrderHash = preCalculateConditionalOrderHash(ammData);

        vm.prank(address(safe));
        vm.expectEmit();
        emit CowAmmModule.CowAmmClosed(safe, previousOrderHash);
        vm.expectEmit();
        emit CowAmmModule.CowAmmCreated(safe, token0, token1, newPreCalculatedOrderHash);

        bytes32 orderHash = cowAmmModule.replaceAmm(
            ammData.minTradedToken0, address(ammData.priceOracle), ammData.priceOracleData, ammData.appData
        );

        assertTrue(orderHash != previousOrderHash);
        assertEq(orderHash, cowAmmModule.activeOrders(safe));
        assertFalse(composableCow.singleOrders(address(safe), previousOrderHash));
        assertTrue(composableCow.singleOrders(address(safe), orderHash));
    }

    function testReplaceAmmWhenNonExists() public {
        setUpDefaultSafe();

        assertTrue(cowAmmModule.activeOrders(safe) == bytes32(0));

        ConstantProduct.Data memory ammData = getDefaultData();

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(CowAmmModule.NoActiveOrderToReplace.selector));

        bytes32 orderHash = cowAmmModule.replaceAmm(
            ammData.minTradedToken0, address(ammData.priceOracle), ammData.priceOracleData, ammData.appData
        );
    }
}
