// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseComposableCoWTest} from "lib/composable-cow/test/ComposableCoW.base.t.sol";

import {ConstantProduct, IERC20, GPv2Order, ISettlement} from "src/ConstantProduct.sol";
import {ConstantProductFactory} from "src/ConstantProductFactory.sol";
import {ConstantProductHelper} from "src/ConstantProductHelper.sol";
import {
    GPv2Settlement,
    GPv2Trade,
    GPv2Signing,
    GPv2Interaction
} from "lib/composable-cow/lib/cowprotocol/src/contracts/GPv2Settlement.sol";

contract ConstantProductHelperForkedTest is Test {
    using GPv2Order for GPv2Order.Data;

    // All hardcoded addresses are mainnet addresses

    GPv2Settlement private settlement = GPv2Settlement(payable(0x9008D19f58AAbD9eD0D60971565AA8510560ab41));
    address private vaultRelayer;
    address private solver = 0x423cEc87f19F0778f549846e0801ee267a917935;

    ConstantProductFactory private ammFactory = ConstantProductFactory(0x8deEd8ED7C5fCB55884f13F121654Bb4bb7c8437);

    IERC20 private USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address private wethUsdcAmm = 0x301076c36E034948A747BB61bAB9CD03f62672e3;

    ConstantProductHelper helper;

    function setUp() public {
        helper = new ConstantProductHelper();
        vaultRelayer = address(settlement.vaultRelayer());
    }

    function testOrder() public {
        uint256 ammWethInitialBalance = WETH.balanceOf(address(wethUsdcAmm));
        uint256 ammUsdcInitialBalance = USDC.balanceOf(address(wethUsdcAmm));

        // We send funds to the settlement contract to be able to settle the AMM
        // rebalancing order without counterpart.
        uint256 wethBuffer = 1_000_000 ether;
        vm.deal(address(settlement), wethBuffer);
        // Wrap ETH
        vm.prank(address(settlement));
        (bool result,) = address(WETH).call{value: wethBuffer}(hex"");
        require(result, "ETH wrapping failed");
        assertGe(WETH.balanceOf(address(settlement)), wethBuffer);

        // Verify that the tokens are the expected ones.
        IERC20[] memory tokens = addressVecToIerc20Vec(helper.tokens(wethUsdcAmm));
        uint256 usdcIndex = 0;
        uint256 wethIndex = 1;
        assertEq(tokens.length, 2);
        assertEq(address(tokens[usdcIndex]), address(USDC));
        assertEq(address(tokens[wethIndex]), address(WETH));

        // Prepare the price vector used in the execution of the settlement in
        // CoW Protocol. We skew the price by ~5% towards a cheaper WETH, so
        // that the AMM wants to buy WETH.
        uint256[] memory prices = new uint256[](2);
        // Note: oracle price are expressed in the same format as prices in
        // a call to `settle`, where the  price vector is expressed so that
        // if the first token is DAI and the second WETH then a price of 3000
        // DAI per WETH means a price vector of [1, 3000] (if the decimals are
        // different, as in WETH/USDC, then the atom amount is what counts).
        prices[usdcIndex] = WETH.balanceOf(wethUsdcAmm);
        prices[wethIndex] = USDC.balanceOf(wethUsdcAmm) * 95 / 100;

        // Prepare the vector storing the one trade to be used in the
        // settlement.
        GPv2Trade.Data[] memory trades = new GPv2Trade.Data[](1);

        // The helper generates the AMM order
        GPv2Order.Data memory ammOrder;
        GPv2Interaction.Data[] memory preInteractions;
        GPv2Interaction.Data[] memory postInteractions;
        bytes memory sig;
        (ammOrder, preInteractions, postInteractions, sig) = helper.order(wethUsdcAmm, prices);
        // The signature is valid for the contract but not for the
        // settlement contract. We need to prepend the verifying contract
        // address.
        // DISCUSS: should we change that?
        sig = abi.encodePacked(wethUsdcAmm, sig);
        trades[0] = orderToFullTrade(ammOrder, tokens, GPv2Signing.Scheme.Eip1271, sig);

        // We expect a commit interaction in both pre and post interactions
        assertEq(preInteractions.length, 1);
        assertEq(postInteractions.length, 1);

        // Because of how we changed the price, we expect to buy USDC
        assertEq(address(ammOrder.sellToken), address(USDC));
        assertEq(address(ammOrder.buyToken), address(WETH));
        // Check that the amounts and price aren't unreasonable. We changed the
        // price by about 5%, so the amounts aren't expected to change
        // significantly more (say, they are between 2% and 3% of the original
        // balance).
        assertGt(ammOrder.sellAmount, ammUsdcInitialBalance * 2 / 100);
        assertLt(ammOrder.sellAmount, ammUsdcInitialBalance * 3 / 100);
        assertGt(ammOrder.buyAmount, ammWethInitialBalance * 2 / 100);
        assertLt(ammOrder.buyAmount, ammWethInitialBalance * 3 / 100);

        GPv2Interaction.Data[][3] memory interactions;
        interactions[0] = preInteractions;
        // No interactions are prescribed.
        interactions[1] = new GPv2Interaction.Data[](0);
        interactions[2] = postInteractions;

        vm.prank(solver);
        // Note that settling also verifies that the price vector is viable for
        // the generated order.
        settlement.settle(tokens, prices, trades, interactions);
    }

    function orderToFullTrade(
        GPv2Order.Data memory order,
        IERC20[] memory tokens,
        GPv2Signing.Scheme signingScheme,
        bytes memory signature
    ) internal pure returns (GPv2Trade.Data memory trade) {
        trade = GPv2Trade.Data({
            sellTokenIndex: findTokenIndex(order.sellToken, tokens),
            buyTokenIndex: findTokenIndex(order.buyToken, tokens),
            receiver: order.receiver,
            sellAmount: order.sellAmount,
            buyAmount: order.buyAmount,
            validTo: order.validTo,
            appData: order.appData,
            feeAmount: order.feeAmount,
            flags: encodeFlags(order, signingScheme),
            executedAmount: order.kind == GPv2Order.KIND_SELL ? order.sellAmount : order.buyAmount,
            signature: signature
        });
    }

    function encodeFlags(GPv2Order.Data memory order, GPv2Signing.Scheme scheme) private pure returns (uint256 flags) {
        if (order.kind == GPv2Order.KIND_BUY) {
            flags |= 1 << 0;
        }

        if (order.partiallyFillable) {
            flags |= 1 << 1;
        }

        if (order.sellTokenBalance == GPv2Order.BALANCE_EXTERNAL) {
            flags |= 2 << 2;
        } else if (order.sellTokenBalance == GPv2Order.BALANCE_INTERNAL) {
            flags |= 3 << 2;
        }

        if (order.buyTokenBalance == GPv2Order.BALANCE_INTERNAL) {
            flags |= 1 << 4;
        } else if (order.buyTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert("Invalid buy token balance");
        }

        if (scheme == GPv2Signing.Scheme.EthSign) {
            flags |= 1 << 5;
        } else if (scheme == GPv2Signing.Scheme.Eip1271) {
            flags |= 2 << 5;
        } else if (scheme == GPv2Signing.Scheme.PreSign) {
            flags |= 3 << 5;
        }
    }

    function findTokenIndex(IERC20 token, IERC20[] memory tokens) private pure returns (uint256) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return i;
            }
        }
        revert("token not found");
    }

    function addressVecToIerc20Vec(address[] memory addrVec) private pure returns (IERC20[] memory ierc20vec) {
        assembly {
            ierc20vec := addrVec
        }
    }
}
