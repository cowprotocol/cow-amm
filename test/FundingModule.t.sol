// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0 <0.9.0;

import "./FundingModule/FundingModuleTestHarness.sol";
import "lib/composable-cow/src/types/twap/TWAP.sol";

contract FundingModuleTestE2E is FundingModuleTestHarness {
    function setUp() public virtual override(FundingModuleTestHarness) {
        super.setUp();
        setUpTokenAmounts();
    }

    function testFundingModuleE2E() public {
        setUpComposableCow();
        setUpTrampoline();

        // 1. Fund the source safe with the funding amount
        setUpTokenAmounts();

        // 2. Fund the destination safe with some AMM tokens (initial)
        setUpAmmReserves();

        // 3. Ensure that the staging safe has allowance on the source safe
        //    NOTE: This is already handled in `super.setUp()`

        // 4. Create the TWAP on the staging safe
        TWAPOrder.Data memory twapData = getTWAPOrder();
        uint256 startTime = block.timestamp + 1 minutes;
        vm.warp(startTime);
        IConditionalOrder.ConditionalOrderParams memory params =
            super.createOrder(twap, keccak256("twap"), abi.encode(twapData));
        _createWithContext(address(stagingSafe), params, currentBlockTimestampFactory, bytes(""), false);

        // 5. Make sure the vault relayer has sufficient allowance on the staging safe
        vm.prank(address(stagingSafe));
        token0.approve(address(relayer), twapData.n * twapData.partSellAmount);

        // 6. Setup the hooks
        HooksTrampoline.Hook[] memory preHooks = new HooksTrampoline.Hook[](1);
        preHooks[0] = HooksTrampoline.Hook({
            target: address(fundingModule),
            callData: abi.encodeWithSelector(FundingModule.pull.selector),
            gasLimit: 50000
        });
        HooksTrampoline.Hook[] memory postHooks = new HooksTrampoline.Hook[](1);
        postHooks[0] = HooksTrampoline.Hook({
            target: address(fundingModule),
            callData: abi.encodeWithSelector(FundingModule.push.selector),
            gasLimit: 40000
        });

        // 7. Iterate over each part of the TWAP and settle it
        for (uint256 i = 0; i < twapData.n; i++) {
            vm.warp(startTime + (i * twapData.t));

            // 7.2. Get the order and signature for the current part of the TWAP
            (GPv2Order.Data memory order, bytes memory signature) =
                composableCow.getTradeableOrderWithSignature(address(stagingSafe), params, bytes(""), new bytes32[](0));

            // 7.3. Settle the current part of the TWAP
            settleWithHooks(address(stagingSafe), bob, order, signature, bytes4(0), preHooks, postHooks);
        }

        // Checks
        assertEq(token0.balanceOf(address(fundingSrc)), FUNDING_AMOUNT - (twapData.n * twapData.partSellAmount));
        assertEq(token0.balanceOf(address(stagingSafe)), 0);
        assertEq(token1.balanceOf(address(stagingSafe)), 0);
    }
}
