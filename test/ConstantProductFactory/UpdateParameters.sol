// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {
    IPriceOracle,
    ConstantProduct,
    ConstantProductFactory,
    ComposableCoW,
    IConditionalOrder
} from "src/ConstantProductFactory.sol";

import {Utils} from "test/libraries/Utils.sol";
import {ConstantProductFactoryTestHarness} from "./ConstantProductFactoryTestHarness.sol";

abstract contract UpdateParameters is ConstantProductFactoryTestHarness {
    uint256 private initMinTradedToken0 = 42;
    uint256 private newMinTradedToken0 = 1337;
    IPriceOracle private initPriceOracle = IPriceOracle(Utils.addressFromString("UpdateParameters: price oracle"));
    IPriceOracle private newPriceOracle =
        IPriceOracle(Utils.addressFromString("UpdateParameters: updated price oracle"));
    bytes private initPriceOracleData = bytes("some price oracle data");
    bytes private newPriceOracleData = bytes("some updated price oracle data");
    bytes32 private initAppData = keccak256("UpdateParameters: app data");
    bytes32 private newAppData = keccak256("UpdateParameters: updated app data");

    function testOnlyOwnerCanUpdateParams() public {
        address notTheOwner = Utils.addressFromString("some address that isn't the owner");
        ConstantProduct amm = setupInitialAMM();
        require(constantProductFactory.owner(amm) != notTheOwner, "bad test setup");

        vm.expectRevert(abi.encodeWithSelector(ConstantProductFactory.OnlyOwnerCanCall.selector, address(this)));
        vm.prank(notTheOwner);
        constantProductFactory.updateParameters(amm, newMinTradedToken0, newPriceOracle, newPriceOracleData, newAppData);
    }

    function testUpdatesTradingParamsHash() public {
        ConstantProduct amm = setupInitialAMM();
        ConstantProduct.TradingParams memory params = ConstantProduct.TradingParams({
            minTradedToken0: newMinTradedToken0,
            priceOracle: newPriceOracle,
            priceOracleData: newPriceOracleData,
            appData: newAppData
        });
        bytes32 newParamsHash = amm.hash(params);

        require(amm.tradingParamsHash() != newParamsHash, "bad test setup");
        constantProductFactory.updateParameters(amm, newMinTradedToken0, newPriceOracle, newPriceOracleData, newAppData);
        assertEq(amm.tradingParamsHash(), newParamsHash);
    }

    function testUpdatingEmitsExpectedEvents() public {
        ConstantProduct amm = setupInitialAMM();
        ConstantProduct.TradingParams memory params = ConstantProduct.TradingParams({
            minTradedToken0: newMinTradedToken0,
            priceOracle: newPriceOracle,
            priceOracleData: newPriceOracleData,
            appData: newAppData
        });

        vm.expectEmit();
        emit ConstantProductFactory.TradingDisabled(amm, address(this));
        vm.expectEmit();
        emit ConstantProductFactory.TradingEnabled(amm, address(this));
        vm.expectEmit();
        emit ComposableCoW.ConditionalOrderCreated(
            address(amm),
            IConditionalOrder.ConditionalOrderParams(
                IConditionalOrder(address(constantProductFactory)), bytes32(0), abi.encode(params)
            )
        );
        constantProductFactory.updateParameters(amm, newMinTradedToken0, newPriceOracle, newPriceOracleData, newAppData);
    }

    function setupInitialAMM() private returns (ConstantProduct) {
        uint256 amount0 = 12345;
        uint256 amount1 = 67890;
        mocksForTokenCreation(
            constantProductFactory.ammDeterministicAddress(address(this), mockableToken0, mockableToken1)
        );
        return constantProductFactory.create(
            mockableToken0,
            amount0,
            mockableToken1,
            amount1,
            initMinTradedToken0,
            initPriceOracle,
            initPriceOracleData,
            initAppData
        );
    }
}
