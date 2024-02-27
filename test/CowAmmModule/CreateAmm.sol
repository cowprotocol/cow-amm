// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {
    CowAmmModuleTestHarness,
    CowAmmModule,
    ConstantProduct,
    IConditionalOrder,
    ComposableCoW,
    SignatureVerifierMuxer
} from "./CowAmmModuleTestHarness.sol";
import {FallbackManager} from "lib/composable-cow/lib/safe/contracts/Safe.sol";

abstract contract CreateAmmTest is CowAmmModuleTestHarness {
    function testCreateAmm() public {
        setUpDefaultSafe();

        ConstantProduct.Data memory ammData = getDefaultData();
        bytes32 domainSeparator = settlement.domainSeparator();

        bytes32 preCalculatedOrderHash = preCalculateConditionalOrderHash(ammData);

        vm.prank(address(safe));

        // Verify `ChangedFallbackHandler` and should be set to `eHandler`
        // We do this to ensure that the fallback handler is set to the expected value
        // as observing the handler directly is not possible
        vm.expectEmit();
        emit FallbackManager.ChangedFallbackHandler(address(eHandler));
        vm.expectEmit();
        emit CowAmmModule.CowAmmCreated(safe, token0, token1, preCalculatedOrderHash);

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
        assertEq(preCalculatedOrderHash, orderHash);
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

    function testFallbackHandlerSetDoesNotSetAgain() public {
        setUpDefaultSafe();

        ConstantProduct.Data memory ammData = getDefaultData();

        vm.mockCallRevert(
            address(safe),
            abi.encodeWithSelector(FallbackManager.setFallbackHandler.selector),
            abi.encode("called setFallbackHandler")
        );
        vm.prank(address(safe));
        vm.expectRevert();
        cowAmmModule.createAmm(
            ammData.token0,
            ammData.token1,
            ammData.minTradedToken0,
            address(ammData.priceOracle),
            ammData.priceOracleData,
            ammData.appData
        );
    }

    function testDomainVerifierSetDoesNotSetAgain() public {
        setUpDefaultSafe();

        ConstantProduct.Data memory ammData = getDefaultData();

        vm.mockCallRevert(
            address(eHandler),
            abi.encodeWithSelector(SignatureVerifierMuxer.setDomainVerifier.selector),
            abi.encode("called setDomainVerifier")
        );
        vm.prank(address(safe));
        vm.expectRevert();
        cowAmmModule.createAmm(
            ammData.token0,
            ammData.token1,
            ammData.minTradedToken0,
            address(ammData.priceOracle),
            ammData.priceOracleData,
            ammData.appData
        );
    }

    function testRevertCalledFromSafeWithoutModuleEnabled() public {
        ConstantProduct.Data memory ammData = getDefaultData();

        deal(address(ammData.token0), address(safe1), 100);
        deal(address(ammData.token1), address(safe1), 100);

        vm.prank(address(safe1));
        vm.expectRevert("GS104");
        cowAmmModule.createAmm(
            ammData.token0,
            ammData.token1,
            ammData.minTradedToken0,
            address(ammData.priceOracle),
            ammData.priceOracleData,
            ammData.appData
        );
    }

    function testRevertCalledFromNonSafe() public {
        ConstantProduct.Data memory ammData = getDefaultData();

        deal(address(ammData.token0), address(alice.addr), 100);
        deal(address(ammData.token1), address(alice.addr), 100);

        vm.prank(address(alice.addr));
        vm.expectRevert();
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
