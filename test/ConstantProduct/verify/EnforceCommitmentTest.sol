// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Utils} from "test/libraries/Utils.sol";
import {ConstantProductTestHarness} from "../ConstantProductTestHarness.sol";
import {ConstantProduct, GPv2Order, IERC20, IConditionalOrder} from "../../../src/ConstantProduct.sol";

abstract contract EnforceCommitmentTest is ConstantProductTestHarness {
    bytes32 private orderHash = keccak256("some order hash");
    bytes32 private orderHashAlternative = keccak256("some other order hash");

    function testRevertsIfCommitDoesNotMatch() public {
        vm.prank(solutionSettler);
        constantProduct.commit(orderOwner, orderHash);
        GPv2Order.Data memory order = getDefaultOrder();
        ConstantProduct.Data memory data = getDefaultData();

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "commitment not matching"));
        verifyWrapper(orderOwner, orderHashAlternative, data, order);
    }

    function testTradeableOrderPassesValidationWithZeroCommit() public {
        require(
            constantProduct.commitment(orderOwner) == constantProduct.EMPTY_COMMITMENT(),
            "test expects unset commitment"
        );

        ConstantProduct.Data memory defaultData = getDefaultData();
        setUpDefaultReserves(orderOwner);
        setUpDefaultReferencePairReserves(42, 1337);

        GPv2Order.Data memory order = getTradeableOrderUncheckedWrapper(orderOwner, defaultData);
        verifyWrapper(orderOwner, orderHash, defaultData, order);
    }

    function testZeroCommitRevertsForOrdersOtherThanTradeableOrder() public {
        require(
            constantProduct.commitment(orderOwner) == constantProduct.EMPTY_COMMITMENT(),
            "test expects unset commitment"
        );

        ConstantProduct.Data memory defaultData = getDefaultData();
        setUpDefaultReserves(orderOwner);
        setUpDefaultReferencePairReserves(42, 1337);

        GPv2Order.Data memory originalOrder = getTradeableOrderUncheckedWrapper(orderOwner, defaultData);
        GPv2Order.Data memory modifiedOrder;

        // All GPv2Order.Data parameters are included in this test. They are:
        // - IERC20 sellToken;
        // - IERC20 buyToken;
        // - address receiver;
        // - uint256 sellAmount;
        // - uint256 buyAmount;
        // - uint32 validTo;
        // - bytes32 appData;
        // - uint256 feeAmount;
        // - bytes32 kind;
        // - bool partiallyFillable;
        // - bytes32 sellTokenBalance;
        // - bytes32 buyTokenBalance;

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.sellToken = IERC20(Utils.addressFromString("bad sell token"));
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "getTradeableOrder not matching")
        );
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.buyToken = IERC20(Utils.addressFromString("bad buy token"));
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "getTradeableOrder not matching")
        );
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.receiver = Utils.addressFromString("bad receiver");
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "receiver must be zero address")
        );
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.sellAmount = modifiedOrder.sellAmount - 1;
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "getTradeableOrder not matching")
        );
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.buyAmount = modifiedOrder.buyAmount + 1;
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "getTradeableOrder not matching")
        );
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.validTo = modifiedOrder.validTo - 1;
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "getTradeableOrder not matching")
        );
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.appData = keccak256("bad app data");
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid appData"));
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.feeAmount = modifiedOrder.feeAmount + 1;
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "fee amount must be zero"));
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.kind = GPv2Order.KIND_BUY;
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "getTradeableOrder not matching")
        );
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.partiallyFillable = !modifiedOrder.partiallyFillable;
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "getTradeableOrder not matching")
        );
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.sellTokenBalance = GPv2Order.BALANCE_EXTERNAL;
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "sellTokenBalance must be erc20")
        );
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);

        modifiedOrder = deepClone(originalOrder);
        modifiedOrder.buyTokenBalance = GPv2Order.BALANCE_EXTERNAL;
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "buyTokenBalance must be erc20")
        );
        verifyWrapper(orderOwner, orderHash, defaultData, modifiedOrder);
    }

    function deepClone(GPv2Order.Data memory order) internal pure returns (GPv2Order.Data memory) {
        return abi.decode(abi.encode(order), (GPv2Order.Data));
    }
}
