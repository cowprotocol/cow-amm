// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0 <0.9.0;

import "lib/composable-cow/test/ComposableCoW.base.t.sol";
import {
    GPv2Trade,
    GPv2Interaction,
    GPv2Signing
} from "lib/composable-cow/lib/cowprotocol/src/contracts/GPv2Settlement.sol";
import {GPv2TradeEncoder} from "lib/composable-cow/test/vendored/GPv2TradeEncoder.sol";
import "lib/composable-cow/src/value_factories/CurrentBlockTimestampFactory.sol";
import "lib/composable-cow/src/types/twap/TWAP.sol";
import {FundingModule, IERC20, ISafe} from "../../src/FundingModule.sol";
import "lib/hooks-trampoline/src/HooksTrampoline.sol";

abstract contract FundingModuleTestHarness is BaseComposableCoWTest {
    using SafeLib for Safe;
    using TestAccountLib for TestAccount;

    // --- constants
    uint256 constant FUNDING_AMOUNT = 1_000_000e18;
    uint256 constant AMM_TOKEN0_AMOUNT = 50_000e18;
    uint256 constant AMM_TOKEN1_AMOUNT = 100_000e18;
    uint256 constant SELL_AMOUNT = 10_000e18;
    uint256 constant BOUGHT_AMOUNT = 20_000e18;

    // --- variables
    FundingModule fundingModule;
    HooksTrampoline trampoline;
    IValueFactory currentBlockTimestampFactory;
    ISafe stagingSafe;
    address fundingSrc;
    address fundingDst;

    function setUp() public virtual override(BaseComposableCoWTest) {
        super.setUp();

        stagingSafe = ISafe(address(safe1));
        fundingSrc = address(safe2);
        fundingDst = address(safe3);

        // create a funding module
        fundingModule = new FundingModule(
            IERC20(address(token0)), IERC20(address(token1)), stagingSafe, fundingSrc, fundingDst, SELL_AMOUNT
        );

        // enable the funding module on the staging safe
        vm.prank(address(stagingSafe));
        safe1.enableModule(address(fundingModule));

        // set the allowance for the staging safe on the funding src
        vm.prank(address(fundingSrc));
        token0.approve(address(stagingSafe), FUNDING_AMOUNT);
    }

    function setUpTokenAmounts() internal {
        // give the funding amount to the funding source
        deal(address(token0), fundingSrc, FUNDING_AMOUNT);
        // set the staging safe to have no tokens
        deal(address(token0), address(stagingSafe), 0);
    }

    function setUpAmmReserves() internal {
        // set the reserves of the AMM (deal it some tokens)
        deal(address(token0), address(fundingDst), AMM_TOKEN0_AMOUNT);
        deal(address(token1), address(fundingDst), AMM_TOKEN1_AMOUNT);
    }

    function setUpBoughtTokens() internal {
        // deal some tokens to the staging safe to create a residual
        deal(address(token1), address(stagingSafe), BOUGHT_AMOUNT);
    }

    function setUpTrampoline() internal {
        // create a trampoline
        trampoline = new HooksTrampoline(address(settlement));
    }

    function setUpComposableCow() internal {
        // deploy the current block timestamp factory
        currentBlockTimestampFactory = new CurrentBlockTimestampFactory();
    }

    function getTWAPOrder() internal returns (TWAPOrder.Data memory) {
        // Assemble the TWAP bundle
        TWAPOrder.Data memory bundle = TWAPOrder.Data({
            sellToken: token0,
            buyToken: token1,
            receiver: address(stagingSafe),
            partSellAmount: SELL_AMOUNT,
            minPartLimit: 1,
            t0: 0,
            n: 10,
            t: 3600,
            span: 0,
            // The below appData should be set correctly for the hooks when
            // used on-chain in the real system.
            appData: keccak256("twapWithHooks")
        });
        return bundle;
    }

    function settleWithHooks(
        address who,
        TestAccount memory counterParty,
        GPv2Order.Data memory order,
        bytes memory bundleBytes,
        bytes4 _revertSelector,
        HooksTrampoline.Hook[] memory preHooks,
        HooksTrampoline.Hook[] memory postHooks
    ) internal {
        // Generate counter party's order
        GPv2Order.Data memory counterOrder = GPv2Order.Data({
            sellToken: order.buyToken,
            buyToken: order.sellToken,
            receiver: address(0),
            sellAmount: order.buyAmount,
            buyAmount: order.sellAmount,
            validTo: order.validTo,
            appData: order.appData,
            feeAmount: 0,
            kind: GPv2Order.KIND_BUY,
            partiallyFillable: false,
            buyTokenBalance: GPv2Order.BALANCE_ERC20,
            sellTokenBalance: GPv2Order.BALANCE_ERC20
        });

        bytes memory counterPartySig =
            counterParty.signPacked(GPv2Order.hash(counterOrder, settlement.domainSeparator()));

        // Authorize the GPv2VaultRelayer to spend bob's sell token
        vm.prank(counterParty.addr);
        IERC20(counterOrder.sellToken).approve(address(relayer), counterOrder.sellAmount);

        // first declare the tokens we will be trading
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(order.sellToken);
        tokens[1] = IERC20(order.buyToken);

        // second declare the clearing prices
        uint256[] memory clearingPrices = new uint256[](2);
        clearingPrices[0] = counterOrder.sellAmount;
        clearingPrices[1] = counterOrder.buyAmount;

        // third declare the trades
        GPv2Trade.Data[] memory trades = new GPv2Trade.Data[](2);

        // The safe's order is the first trade
        trades[0] = GPv2Trade.Data({
            sellTokenIndex: 0,
            buyTokenIndex: 1,
            receiver: order.receiver,
            sellAmount: order.sellAmount,
            buyAmount: order.buyAmount,
            validTo: order.validTo,
            appData: order.appData,
            feeAmount: order.feeAmount,
            flags: GPv2TradeEncoder.encodeFlags(order, GPv2Signing.Scheme.Eip1271),
            executedAmount: order.sellAmount,
            signature: abi.encodePacked(who, bundleBytes)
        });

        // Bob's order is the second trade
        trades[1] = GPv2Trade.Data({
            sellTokenIndex: 1,
            buyTokenIndex: 0,
            receiver: address(0),
            sellAmount: counterOrder.sellAmount,
            buyAmount: counterOrder.buyAmount,
            validTo: counterOrder.validTo,
            appData: counterOrder.appData,
            feeAmount: counterOrder.feeAmount,
            flags: GPv2TradeEncoder.encodeFlags(counterOrder, GPv2Signing.Scheme.Eip712),
            executedAmount: counterOrder.sellAmount,
            signature: counterPartySig
        });

        // fourth declare the interactions
        GPv2Interaction.Data[][3] memory interactions =
            [wrapHooks(preHooks), new GPv2Interaction.Data[](0), wrapHooks(postHooks)];

        // finally we can execute the settlement
        vm.prank(solver.addr);
        if (_revertSelector == bytes4(0)) {
            settlement.settle(tokens, clearingPrices, trades, interactions);
        } else {
            vm.expectRevert(_revertSelector);
            settlement.settle(tokens, clearingPrices, trades, interactions);
        }
    }

    function wrapHooks(HooksTrampoline.Hook[] memory hooks)
        internal
        returns (GPv2Interaction.Data[] memory trampolined)
    {
        trampolined = new GPv2Interaction.Data[](1);
        trampolined[0] = GPv2Interaction.Data({
            target: address(trampoline),
            callData: abi.encodeWithSelector(trampoline.execute.selector, hooks),
            value: 0
        });
    }
}
