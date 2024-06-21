// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IERC20, IPriceOracle, ConstantProduct, ConstantProductFactory} from "src/ConstantProductFactory.sol";

import {ConstantProductFactoryTestHarness} from "../ConstantProductFactoryTestHarness.sol";

abstract contract CreateAMM is ConstantProductFactoryTestHarness {
    uint256 private amount0 = 1234;
    uint256 private amount1 = 5678;
    uint256 private minTradedToken0 = 42;
    IPriceOracle private priceOracle = IPriceOracle(makeAddr("Create: price oracle"));
    bytes private priceOracleData = bytes("some price oracle data");
    bytes32 private appData = keccak256("Create: app data");

    function testNewAMMHasExpectedTokens() public {
        mocksForTokenCreation(
            constantProductFactory.ammDeterministicAddress(address(this), mockableToken0, mockableToken1)
        );

        ConstantProduct amm = constantProductFactory.create(mockableToken0, amount0, mockableToken1, amount1);
        assertEq(address(amm.token0()), address(mockableToken0));
        assertEq(address(amm.token1()), address(mockableToken1));
    }

    function testNewAMMEnablesTrading() public {
        mocksForTokenCreation(
            constantProductFactory.ammDeterministicAddress(address(this), mockableToken0, mockableToken1)
        );

        ConstantProduct amm = constantProductFactory.create(mockableToken0, amount0, mockableToken1, amount1);
        assertEq(amm.tradingEnabled(), true);
    }

    function testCreationTransfersInExpectedAmounts() public {
        address expectedAMM =
            constantProductFactory.ammDeterministicAddress(address(this), mockableToken0, mockableToken1);
        mocksForTokenCreation(expectedAMM);

        vm.expectCall(
            address(mockableToken0), abi.encodeCall(IERC20.transferFrom, (address(this), expectedAMM, amount0)), 1
        );
        vm.expectCall(
            address(mockableToken1), abi.encodeCall(IERC20.transferFrom, (address(this), expectedAMM, amount1)), 1
        );
        constantProductFactory.create(mockableToken0, amount0, mockableToken1, amount1);
    }

    function testCreationSetsOwner() public {
        ConstantProduct expectedAMM = ConstantProduct(
            constantProductFactory.ammDeterministicAddress(address(this), mockableToken0, mockableToken1)
        );
        mocksForTokenCreation(address(expectedAMM));
        require(constantProductFactory.owner(expectedAMM) == address(0), "Initial owner is expected to be unset");

        constantProductFactory.create(mockableToken0, amount0, mockableToken1, amount1);
        assertFalse(constantProductFactory.owner(expectedAMM) == address(0));
        assertEq(constantProductFactory.owner(expectedAMM), address(this));
    }

    function testCreationEmitsEvents() public {
        address expectedAMM =
            constantProductFactory.ammDeterministicAddress(address(this), mockableToken0, mockableToken1);
        mocksForTokenCreation(address(expectedAMM));

        vm.expectEmit();
        emit ConstantProductFactory.Deployed(
            ConstantProduct(expectedAMM), address(this), mockableToken0, mockableToken1
        );
        vm.expectEmit();
        emit ConstantProductFactory.TradingEnabled(ConstantProduct(expectedAMM));
        constantProductFactory.create(mockableToken0, amount0, mockableToken1, amount1);
    }
}
