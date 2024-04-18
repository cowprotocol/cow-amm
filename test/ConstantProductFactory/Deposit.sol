// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "src/ConstantProductFactory.sol";

import {Utils} from "test/libraries/Utils.sol";
import {ConstantProductFactoryTestHarness} from "./ConstantProductFactoryTestHarness.sol";

abstract contract Deposit is ConstantProductFactoryTestHarness {
    function testAnyoneCanDeposit() public {
        address anyone = Utils.addressFromString("Deposit: an arbitrary address");
        uint256 amount0 = 1234;
        uint256 amount1 = 5678;

        address token0 = address(constantProduct.token0());
        address token1 = address(constantProduct.token1());
        vm.expectCall(token0, abi.encodeCall(IERC20.transferFrom, (anyone, address(constantProduct), amount0)), 1);
        vm.expectCall(token1, abi.encodeCall(IERC20.transferFrom, (anyone, address(constantProduct), amount1)), 1);
        vm.prank(anyone);
        constantProductFactory.deposit(constantProduct, amount0, amount1);
    }

    function testOnlyCallsTransferFromOnDeposit() public {
        uint256 amount0 = 1234;
        uint256 amount1 = 5678;

        address token0 = address(constantProduct.token0());
        address token1 = address(constantProduct.token1());
        vm.mockCall(
            token0, abi.encodeCall(IERC20.transferFrom, (address(this), address(constantProduct), amount0)), hex""
        );
        vm.mockCall(
            token1, abi.encodeCall(IERC20.transferFrom, (address(this), address(constantProduct), amount1)), hex""
        );

        // No more calls to the tokens are expected.
        vm.mockCallRevert(token0, hex"", "Unexpected call to token0");
        vm.mockCallRevert(token1, hex"", "Unexpected call to token1");

        constantProductFactory.deposit(constantProduct, amount0, amount1);
    }

    function testRevertsIfTokenReturnsFalseOnDeposit() public {
        uint256 amount0 = 1234;
        uint256 amount1 = 5678;

        //constantProductFactory.setOwner(constantProduct, owner);
        address token0 = address(constantProduct.token0());
        address token1 = address(constantProduct.token1());
        vm.mockCall(
            token0, abi.encodeCall(IERC20.transferFrom, (address(this), address(constantProduct), amount0)), hex""
        );
        vm.mockCall(
            token1,
            abi.encodeCall(IERC20.transferFrom, (address(this), address(constantProduct), amount1)),
            abi.encode(false)
        );

        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        constantProductFactory.deposit(constantProduct, amount0, amount1);
    }

    function testRevertsIfAnyDepositReverts() public {
        uint256 amount0 = 1234;
        uint256 amount1 = 5678;

        //constantProductFactory.setOwner(constantProduct, owner);
        address token0 = address(constantProduct.token0());
        address token1 = address(constantProduct.token1());
        vm.mockCall(
            token0, abi.encodeCall(IERC20.transferFrom, (address(this), address(constantProduct), amount0)), hex""
        );
        vm.mockCallRevert(
            token1,
            abi.encodeCall(IERC20.transferFrom, (address(this), address(constantProduct), amount1)),
            "this transfer reverted"
        );

        vm.expectRevert("this transfer reverted");
        constantProductFactory.deposit(constantProduct, amount0, amount1);
    }
}
