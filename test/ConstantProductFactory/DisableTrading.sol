// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ConstantProduct, ConstantProductFactory} from "src/ConstantProductFactory.sol";

import {Utils} from "test/libraries/Utils.sol";
import {ConstantProductFactoryTestHarness} from "./ConstantProductFactoryTestHarness.sol";

abstract contract DisableTrading is ConstantProductFactoryTestHarness {
    function testOnlyOwnerCanDisableTrading() public {
        address notTheOwner = Utils.addressFromString("some address that isn't the owner");
        ConstantProduct amm = setupAndCreateAMM();
        require(constantProductFactory.owner(amm) != notTheOwner, "bad test setup");

        vm.expectRevert(abi.encodeWithSelector(ConstantProductFactory.OnlyOwnerCanCall.selector, address(this)));
        vm.prank(notTheOwner);
        constantProductFactory.disableTrading(amm);
    }

    function testResetsTradingParamsHash() public {
        ConstantProduct amm = setupAndCreateAMM();

        constantProductFactory.disableTrading(amm);
        assertEq(amm.tradingParamsHash(), amm.NO_TRADING());
    }

    function testDisableTradingEmitsExpectedEvents() public {
        ConstantProduct amm = setupAndCreateAMM();

        vm.expectEmit();
        emit ConstantProductFactory.TradingDisabled(amm, address(this));
        constantProductFactory.disableTrading(amm);
    }

    function setupAndCreateAMM() private returns (ConstantProduct) {
        uint256 amount0 = 1234;
        uint256 amount1 = 5678;
        uint256 minTradedToken0 = 42;
        address priceOracle = Utils.addressFromString("DisableTrading: price oracle");
        bytes memory priceOracleData = bytes("some price oracle data");
        bytes32 appData = keccak256("DisableTrading: app data");

        mocksForTokenCreation(addressOfNextDeployedAMM());
        return constantProductFactory.create(
            mockableToken0, amount0, mockableToken1, amount1, minTradedToken0, priceOracle, priceOracleData, appData
        );
    }
}
