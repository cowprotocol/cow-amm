// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {
    IERC20,
    IPriceOracle,
    ConstantProduct,
    ConstantProductFactory,
    ComposableCoW,
    IConditionalOrder
} from "src/ConstantProductFactory.sol";

import {Utils} from "test/libraries/Utils.sol";
import {ConstantProductFactoryTestHarness} from "./ConstantProductFactoryTestHarness.sol";

abstract contract Create is ConstantProductFactoryTestHarness {
    uint256 private amount0 = 1234;
    uint256 private amount1 = 5678;
    uint256 private minTradedToken0 = 42;
    IPriceOracle private priceOracle = IPriceOracle(Utils.addressFromString("Create: price oracle"));
    bytes private priceOracleData = bytes("some price oracle data");
    bytes32 private appData = keccak256("Create: app data");

    function testCreatesAMM() public {
        address constantProductAddress = addressOfNextDeployedAMM();
        require(constantProductAddress.code.length == 0, "no AMM should be deployed at the start");
        mocksForTokenCreation(constantProductAddress);

        ConstantProduct deployed = constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
        assertEq(address(deployed), constantProductAddress);
        assertTrue(constantProductAddress.code.length > 0);
    }

    function testNewAMMHasExpectedTokens() public {
        mocksForTokenCreation(addressOfNextDeployedAMM());

        ConstantProduct amm = constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
        assertEq(address(amm.token0()), address(mockableToken0));
        assertEq(address(amm.token1()), address(mockableToken1));
        ConstantProduct.TradingParams memory params = ConstantProduct.TradingParams({
            minTradedToken0: minTradedToken0,
            priceOracle: priceOracle,
            priceOracleData: priceOracleData,
            appData: appData
        });
        assertEq(amm.tradingParamsHash(), amm.hash(params));
    }

    function testNewAMMEnablesTrading() public {
        mocksForTokenCreation(addressOfNextDeployedAMM());

        ConstantProduct amm = constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
        ConstantProduct.TradingParams memory params = ConstantProduct.TradingParams({
            minTradedToken0: minTradedToken0,
            priceOracle: priceOracle,
            priceOracleData: priceOracleData,
            appData: appData
        });
        assertEq(amm.tradingParamsHash(), amm.hash(params));
    }

    function testCreationTransfersInExpectedAmounts() public {
        address expectedAMM = addressOfNextDeployedAMM();
        mocksForTokenCreation(expectedAMM);

        vm.expectCall(
            address(mockableToken0), abi.encodeCall(IERC20.transferFrom, (address(this), expectedAMM, amount0)), 1
        );
        vm.expectCall(
            address(mockableToken1), abi.encodeCall(IERC20.transferFrom, (address(this), expectedAMM, amount1)), 1
        );
        constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
    }

    function testCreationSetsOwner() public {
        ConstantProduct expectedAMM = ConstantProduct(addressOfNextDeployedAMM());
        mocksForTokenCreation(address(expectedAMM));
        require(constantProductFactory.owner(expectedAMM) == address(0), "Initial owner is expected to be unset");

        constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
        assertFalse(constantProductFactory.owner(expectedAMM) == address(0));
        assertEq(constantProductFactory.owner(expectedAMM), address(this));
    }

    function testCreationEmitsEvents() public {
        address expectedAMM = addressOfNextDeployedAMM();
        mocksForTokenCreation(address(expectedAMM));

        ConstantProduct.TradingParams memory params = ConstantProduct.TradingParams({
            minTradedToken0: minTradedToken0,
            priceOracle: priceOracle,
            priceOracleData: priceOracleData,
            appData: appData
        });
        bytes32 salt = bytes32(bytes20(address(this))) | bytes32(block.timestamp);
        vm.expectEmit();
        emit ConstantProductFactory.TradingEnabled(ConstantProduct(expectedAMM), address(this));
        vm.expectEmit();
        emit ComposableCoW.ConditionalOrderCreated(
            expectedAMM,
            IConditionalOrder.ConditionalOrderParams(
                IConditionalOrder(address(constantProductFactory)), salt, abi.encode(params)
            )
        );
        ConstantProduct amm = constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
    }
}
