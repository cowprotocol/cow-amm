// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Utils} from "test/libraries/Utils.sol";
import {ConstantProductTestHarness, ConstantProduct} from "./ConstantProductTestHarness.sol";

abstract contract CommitTest is ConstantProductTestHarness {
    function testSolutionSettlerCanSetAnyCommit() public {
        vm.prank(address(solutionSettler));
        constantProduct.commit(
            0x1337133713371337133713371337133713371337,
            0x4242424242424242424242424242424242424242424242424242424242424242
        );
    }

    function testCommitIsPermissioned() public {
        vm.prank(Utils.addressFromString("some random address"));
        vm.expectRevert(abi.encodeWithSelector(ConstantProduct.CommitOutsideOfSettlement.selector));
        constantProduct.commit(
            0x1337133713371337133713371337133713371337,
            0x4242424242424242424242424242424242424242424242424242424242424242
        );
    }

    function testCommittingSetsCommitmentInMapping() public {
        address addr = 0x1337133713371337133713371337133713371337;
        bytes32 commitment = 0x4242424242424242424242424242424242424242424242424242424242424242;
        assertEq(constantProduct.commitment(addr), bytes32(0));
        vm.prank(address(solutionSettler));
        constantProduct.commit(addr, commitment);
        assertEq(constantProduct.commitment(addr), commitment);
    }
}
