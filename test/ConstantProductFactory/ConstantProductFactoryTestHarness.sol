// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {
    ConstantProductFactory,
    ConstantProduct,
    GPv2Order,
    IConditionalOrder,
    ISettlement
} from "src/ConstantProductFactory.sol";

import {ConstantProductTestHarness} from "test/ConstantProduct/ConstantProductTestHarness.sol";

abstract contract ConstantProductFactoryTestHarness is ConstantProductTestHarness {
    ConstantProductFactory internal constantProductFactory;

    function setUp() public virtual override(ConstantProductTestHarness) {
        super.setUp();
        constantProductFactory = new ConstantProductFactory(solutionSettler);
    }

    // This function calls `getTradeableOrderWithSignature` while filling all
    // unused parameters with arbitrary data.
    function getTradeableOrderWithSignatureWrapper(
        ConstantProduct amm,
        ConstantProduct.TradingParams memory tradingParams
    ) internal view returns (GPv2Order.Data memory order, bytes memory signature) {
        IConditionalOrder.ConditionalOrderParams memory params = IConditionalOrder.ConditionalOrderParams(
            IConditionalOrder(address(constantProductFactory)),
            keccak256("ConstantProductFactoryTestHarness: some salt"),
            abi.encode(tradingParams)
        );
        return constantProductFactory.getTradeableOrderWithSignature(
            amm, params, bytes("ConstantProductFactoryTestHarness: offchainData"), new bytes32[](2)
        );
    }
}

contract EditableOwnerConstantProductFactory is ConstantProductFactory {
    constructor(ISettlement s) ConstantProductFactory(s) {}

    function setOwner(ConstantProduct amm, address newOwner) external {
        owner[amm] = newOwner;
    }
}
