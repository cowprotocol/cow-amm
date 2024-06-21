// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {ConstantProduct, GPv2Order, IERC20, IConditionalOrder} from "src/ConstantProduct.sol";

import {ConstantProductTestHarness} from "../ConstantProductTestHarness.sol";

abstract contract EnforceCommitmentTest is ConstantProductTestHarness {
    using GPv2Order for GPv2Order.Data;

    function testRevertsIfCommitDoesNotMatch() public {
        bytes32 badCommitment = keccak256("some bad commitment");
        SignatureData memory data = defaultSignatureAndHashes();
        constantProduct.enableTrading();

        setUpDefaultPair();
        vm.prank(address(solutionSettler));
        constantProduct.commit(badCommitment);

        vm.expectRevert(abi.encodeWithSelector(ConstantProduct.OrderDoesNotMatchCommitmentHash.selector));
        constantProduct.isValidSignature(data.orderHash, data.signature);
    }
}
