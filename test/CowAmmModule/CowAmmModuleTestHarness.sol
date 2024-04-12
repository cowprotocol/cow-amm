// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {
    BaseComposableCoWTest,
    IConditionalOrder,
    ComposableCoW,
    ExtensibleFallbackHandler,
    SignatureVerifierMuxer
} from "lib/composable-cow/test/ComposableCoW.base.t.sol";
import {SafeLib, Safe} from "lib/composable-cow/test/libraries/SafeLib.t.sol";

import {CowAmmModule, ConstantProduct} from "src/CowAmmModule.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";
import {Utils} from "test/libraries/Utils.sol";

abstract contract CowAmmModuleTestHarness is BaseComposableCoWTest {
    using SafeLib for Safe;

    address internal orderOwner = address(safe1);
    IPriceOracle internal DEFAULT_PRICE_ORACLE = IPriceOracle(Utils.addressFromString("an oracle"));
    bytes32 private DEFAULT_APPDATA = keccak256(bytes("unit test"));

    Safe internal safe;
    ConstantProduct internal constantProduct;
    CowAmmModule internal cowAmmModule;

    function setUp() public virtual override(BaseComposableCoWTest) {
        super.setUp();

        address[] memory owners = new address[](3);
        owners[0] = alice.addr;
        owners[1] = bob.addr;
        owners[2] = carol.addr;

        safe = Safe(
            payable(
                SafeLib.createSafe(
                    factory, singleton, owners, 2, address(0), Utils.uintFromString("safe creation salt")
                )
            )
        );

        constantProduct = new ConstantProduct(address(settlement), token0, token1);
        cowAmmModule = new CowAmmModule(settlement, eHandler, composableCow, constantProduct, token0, token1);
    }

    function setUpDefaultSafe() internal {
        deal(address(token0), address(safe), 10_000e18);
        deal(address(token1), address(safe), 100_000e18);
        vm.prank(address(safe));
        safe.enableModule(address(cowAmmModule));
    }

    function getDefaultData() internal view returns (ConstantProduct.Data memory) {
        return ConstantProduct.Data(0, DEFAULT_PRICE_ORACLE, bytes("some oracle data"), DEFAULT_APPDATA);
    }

    function setUpDefaultCowAmm() internal {
        setUpDefaultSafe();
        ConstantProduct.Data memory ammData = getDefaultData();

        vm.prank(address(safe));
        cowAmmModule.createAmm(
            ammData.minTradedToken0, address(ammData.priceOracle), ammData.priceOracleData, ammData.appData
        );
    }

    function preCalculateConditionalOrderHash(ConstantProduct.Data memory data) internal view returns (bytes32) {
        // Wrap the data in a conditional order
        IConditionalOrder.ConditionalOrderParams memory params = IConditionalOrder.ConditionalOrderParams({
            handler: constantProduct,
            salt: keccak256(abi.encodePacked(block.timestamp)),
            staticInput: abi.encode(data)
        });

        return composableCow.hash(params);
    }
}
