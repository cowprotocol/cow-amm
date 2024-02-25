// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {CowAmmModuleTestHarness, CowAmmModule, ConstantProduct} from "./CowAmmModuleTestHarness.sol";
import {FallbackManager} from "lib/composable-cow/lib/safe/contracts/Safe.sol";

abstract contract CreateAmmTest is CowAmmModuleTestHarness {
    function testCreateAmm() public {
        setUpDefaultSafe();

        ConstantProduct.Data memory ammData = getDefaultData();
        bytes32 domainSeparator = settlement.domainSeparator();

        vm.prank(address(safe));

        // Verify `ChangedFallbackHandler` and should be set to `eHandler`
        // We do this to ensure that the fallback handler is set to the expected value
        // as observing the handler directly is not possible
        vm.expectEmit(true, true, false, false);
        emit FallbackManager.ChangedFallbackHandler(address(eHandler));
        vm.expectEmit(true, true, true, false);
        emit CowAmmModule.CowAmmCreated(safe, token0, token1, bytes32(0));

        bytes32 orderHash = cowAmmModule.createAmm(
            ammData.token0,
            ammData.token1,
            ammData.minTradedToken0,
            address(ammData.priceOracle),
            ammData.priceOracleData,
            ammData.appData
        );

        assertEq(address(eHandler.domainVerifiers(safe, domainSeparator)), address(composableCow));
        assertEq(token0.allowance(address(safe), address(relayer)), type(uint256).max);
        assertEq(token1.allowance(address(safe), address(relayer)), type(uint256).max);
        assertTrue(composableCow.singleOrders(address(safe), orderHash));
        assertEq(cowAmmModule.activeOrders(safe), orderHash);
    }

    function testRevertIfNoToken0Balance() public {
        _testRevertIfNoTokenBalance(address(token0));
    }

    function testRevertIfNoToken1Balance() public {
        _testRevertIfNoTokenBalance(address(token1));
    }

    function testRevertIfAmmAlreadyExists() public {
        setUpDefaultCowAmm();

        ConstantProduct.Data memory ammData = getDefaultData();

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(CowAmmModule.ActiveAMM.selector));
        cowAmmModule.createAmm(
            ammData.token0,
            ammData.token1,
            ammData.minTradedToken0,
            address(ammData.priceOracle),
            ammData.priceOracleData,
            ammData.appData
        );
    }

    function _testRevertIfNoTokenBalance(address token) internal {
        setUpDefaultSafe();

        ConstantProduct.Data memory ammData = getDefaultData();
        deal(address(token), address(safe), 0);

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(CowAmmModule.TokenBalanceZero.selector));
        cowAmmModule.createAmm(
            ammData.token0,
            ammData.token1,
            ammData.minTradedToken0,
            address(ammData.priceOracle),
            ammData.priceOracleData,
            ammData.appData
        );
    }
}