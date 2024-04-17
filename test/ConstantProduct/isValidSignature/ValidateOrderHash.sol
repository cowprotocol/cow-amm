// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC1271} from "lib/openzeppelin/contracts/interfaces/IERC1271.sol";

import {ConstantProductTestHarness, ConstantProduct} from "../ConstantProductTestHarness.sol";

abstract contract ValidateOrderHash is ConstantProductTestHarness {
    function testRevertsIfStaticInputHashDoesNotMatchTradingParamsHash() public {
        SignatureData memory data = defaultSignatureAndHashes();

        vm.expectRevert(abi.encodeWithSelector(ConstantProduct.TradingParamsDoNotMatchHash.selector));
        constantProduct.isValidSignature(data.orderHash, data.signature);
    }

    function testRevertsIfOrderInSignatureDoesNotMatchOrderHash() public {
        SignatureData memory data = defaultSignatureAndHashes();
        constantProduct.enableTrading(data.tradingParams);

        bytes32 badOrderHash = keccak256("Some invalid order hash");
        vm.expectRevert(abi.encodeWithSelector(ConstantProduct.OrderDoesNotMatchMessageHash.selector));
        constantProduct.isValidSignature(badOrderHash, data.signature);
    }

    function testRevertsIfVerificationFails() public {
        SignatureData memory data = defaultSignatureAndHashes();
        constantProduct.enableTrading(data.tradingParams);

        // There are many ways to trigger failure in _verify. The most robust is
        // likely to just set a commit that is different from the signed order.
        vm.prank(address(solutionSettler));
        constantProduct.commit(keccak256("Any bad commitment"));

        vm.expectRevert(abi.encodeWithSelector(ConstantProduct.OrderDoesNotMatchCommitmentHash.selector));
        constantProduct.isValidSignature(data.orderHash, data.signature);
    }

    function testReturnsMagicValueIfTradeable() public {
        SignatureData memory data = defaultSignatureAndHashes();
        constantProduct.enableTrading(data.tradingParams);

        // Setup to make the order pass verification
        setUpDefaultPair();
        setUpDefaultReserves(address(constantProduct));
        vm.prank(address(solutionSettler));
        constantProduct.commit(data.orderHash);

        // Make sure that the order would pass verification. If this reverts,
        // then this test's setup should be updated.
        constantProduct.verify(data.tradingParams, data.order);

        bytes4 result = constantProduct.isValidSignature(data.orderHash, data.signature);
        assertEq(result, IERC1271.isValidSignature.selector);
    }
}
