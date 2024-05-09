// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IPriceOracle, ConstantProduct, IERC20} from "src/ConstantProductFactory.sol";

import {Utils} from "test/libraries/Utils.sol";
import {ConstantProductFactoryTestHarness} from "../ConstantProductFactoryTestHarness.sol";

abstract contract DeterministicDeployment is ConstantProductFactoryTestHarness {
    uint256 private amount0 = 1234;
    uint256 private amount1 = 5678;
    uint256 private minTradedToken0 = 42;
    IPriceOracle private priceOracle = IPriceOracle(Utils.addressFromString("Create: price oracle"));
    bytes private priceOracleData = bytes("some price oracle data");
    bytes32 private appData = keccak256("Create: app data");

    function testDeploysAtExpectedAddress() public {
        address constantProductAddress =
            constantProductFactory.ammDeterministicAddress(address(this), mockableToken0, mockableToken1);
        require(constantProductAddress.code.length == 0, "no AMM should be deployed at the start");
        mocksForTokenCreation(constantProductAddress);

        ConstantProduct deployed = constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
        assertEq(address(deployed), constantProductAddress);
        assertTrue(constantProductAddress.code.length > 0);
    }

    function testSameOwnerCannotDeployAMMWithSameParametersTwice() public {
        address constantProductAddress =
            constantProductFactory.ammDeterministicAddress(address(this), mockableToken0, mockableToken1);
        mocksForTokenCreation(constantProductAddress);

        constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
        vm.expectRevert(bytes(""));
        constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
    }

    function testSameOwnerCanDeployAMMWithDifferentTokens() public {
        address ammAddress1 =
            constantProductFactory.ammDeterministicAddress(address(this), mockableToken0, mockableToken1);
        mocksForTokenCreation(ammAddress1);

        // Same setup as in `mocksForTokenCreation`, but for newly created tokens.
        IERC20 extraToken0 = IERC20(Utils.addressFromString("DeterministicDeployment: extra token 0"));
        IERC20 extraToken1 = IERC20(Utils.addressFromString("DeterministicDeployment: extra token 1"));
        address ammAddress2 = constantProductFactory.ammDeterministicAddress(address(this), extraToken0, extraToken1);
        setUpTokenForDeployment(extraToken0, ammAddress2, address(constantProductFactory));
        setUpTokenForDeployment(extraToken1, ammAddress2, address(constantProductFactory));

        constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
        constantProductFactory.create(
            extraToken0, amount0, extraToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
    }

    function testDifferentOwnersCanDeployAMMWithSameParameters() public {
        address owner1 = Utils.addressFromString("DeterministicDeployment: owner 1");
        address owner2 = Utils.addressFromString("DeterministicDeployment: owner 2");
        address ammOwner1 = constantProductFactory.ammDeterministicAddress(owner1, mockableToken0, mockableToken1);
        address ammOwner2 = constantProductFactory.ammDeterministicAddress(owner2, mockableToken0, mockableToken1);
        mocksForTokenCreation(ammOwner1);
        mocksForTokenCreation(ammOwner2);

        vm.prank(owner1);
        constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
        vm.prank(owner2);
        constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
    }
}
