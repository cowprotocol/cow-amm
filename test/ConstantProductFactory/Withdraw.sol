// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {ConstantProductFactory, IERC20} from "src/ConstantProductFactory.sol";

import {
    EditableOwnerConstantProductFactory,
    ConstantProductFactoryTestHarness
} from "./ConstantProductFactoryTestHarness.sol";

abstract contract Withdraw is ConstantProductFactoryTestHarness {
    uint256 private amount0 = 1234;
    uint256 private amount1 = 5678;
    address private owner = makeAddr("Deposit: an arbitrary owner");

    function testWithdrawingIsPermissioned() public {
        EditableOwnerConstantProductFactory factory = new EditableOwnerConstantProductFactory(solutionSettler);
        factory.setOwner(constantProduct, owner);
        address notOwner = makeAddr("Deposit: some address that isn't an owner");

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(ConstantProductFactory.OnlyOwnerCanCall.selector, owner));
        factory.withdraw(constantProduct, 1234, 5678);
    }

    function testCallsTransferFromOnWithdraw() public {
        EditableOwnerConstantProductFactory factory = new EditableOwnerConstantProductFactory(solutionSettler);
        factory.setOwner(constantProduct, owner);

        address token0 = address(constantProduct.token0());
        address token1 = address(constantProduct.token1());
        vm.expectCall(token0, abi.encodeCall(IERC20.transferFrom, (address(constantProduct), owner, amount0)), 1);
        vm.expectCall(token1, abi.encodeCall(IERC20.transferFrom, (address(constantProduct), owner, amount1)), 1);

        vm.prank(owner);
        factory.withdraw(constantProduct, amount0, amount1);
    }

    function testOnlyCallsTransferFromOnWithdraw() public {
        EditableOwnerConstantProductFactory factory = new EditableOwnerConstantProductFactory(solutionSettler);
        factory.setOwner(constantProduct, owner);

        address token0 = address(constantProduct.token0());
        address token1 = address(constantProduct.token1());
        vm.mockCall(token0, abi.encodeCall(IERC20.transferFrom, (address(constantProduct), owner, amount0)), hex"");
        vm.mockCall(token1, abi.encodeCall(IERC20.transferFrom, (address(constantProduct), owner, amount1)), hex"");

        // No more calls to the tokens are expected.
        vm.mockCallRevert(token0, hex"", "Unexpected call to token0");
        vm.mockCallRevert(token1, hex"", "Unexpected call to token1");

        vm.prank(owner);
        factory.withdraw(constantProduct, amount0, amount1);
    }

    function testRevertsIfTokenReturnsFalseOnWithdraw() public {
        EditableOwnerConstantProductFactory factory = new EditableOwnerConstantProductFactory(solutionSettler);
        factory.setOwner(constantProduct, owner);

        address token0 = address(constantProduct.token0());
        address token1 = address(constantProduct.token1());
        vm.mockCall(token0, abi.encodeCall(IERC20.transferFrom, (address(constantProduct), owner, amount0)), hex"");
        vm.mockCall(
            token1, abi.encodeCall(IERC20.transferFrom, (address(constantProduct), owner, amount1)), abi.encode(false)
        );

        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        vm.prank(owner);
        factory.withdraw(constantProduct, amount0, amount1);
    }

    function testRevertsIfAnyDepositRevertsOnWithdraw() public {
        EditableOwnerConstantProductFactory factory = new EditableOwnerConstantProductFactory(solutionSettler);
        factory.setOwner(constantProduct, owner);

        address token0 = address(constantProduct.token0());
        address token1 = address(constantProduct.token1());
        vm.mockCall(token0, abi.encodeCall(IERC20.transferFrom, (address(constantProduct), owner, amount0)), hex"");
        vm.mockCallRevert(
            token1,
            abi.encodeCall(IERC20.transferFrom, (address(constantProduct), owner, amount1)),
            "this transfer reverted"
        );

        vm.expectRevert("this transfer reverted");
        vm.prank(owner);
        factory.withdraw(constantProduct, amount0, amount1);
    }
}
