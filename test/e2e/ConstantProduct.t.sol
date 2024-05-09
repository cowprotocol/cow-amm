// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {BaseComposableCoWTest} from "lib/composable-cow/test/ComposableCoW.base.t.sol";

import {ConstantProduct, IERC20, GPv2Order, ISettlement} from "src/ConstantProduct.sol";
import {ConstantProductFactory, IConditionalOrder} from "src/ConstantProductFactory.sol";
import {UniswapV2PriceOracle, IUniswapV2Pair} from "src/oracles/UniswapV2PriceOracle.sol";
import {ISettlement} from "src/interfaces/ISettlement.sol";
import {Utils} from "test/libraries/Utils.sol";
import {UniswapV2Helper, IUniswapV2Factory} from "test/libraries/UniswapV2Helper.sol";

contract E2EConditionalOrderTest is BaseComposableCoWTest {
    using UniswapV2Helper for IUniswapV2Factory;
    using GPv2Order for GPv2Order.Data;

    address public constant owner = 0x1234567890123456789012345678901234567890;
    IERC20 public DAI;
    IERC20 public WETH;
    IUniswapV2Pair pair;
    ConstantProductFactory ammFactory;
    UniswapV2PriceOracle uniswapV2PriceOracle;

    function setUp() public virtual override(BaseComposableCoWTest) {
        super.setUp();
        DAI = token0;
        WETH = token1;
        ammFactory = new ConstantProductFactory(ISettlement(address(settlement)));
        uniswapV2PriceOracle = new UniswapV2PriceOracle();
        IUniswapV2Factory uniswapV2Factory = UniswapV2Helper.deployUniswapV2FactoryAt(
            vm, Utils.addressFromString("E2EConditionalOrderTest UniswapV2 factory")
        );
        pair = createPair(uniswapV2Factory, DAI, 300_000 ether, WETH, 100 ether);
    }

    function createPair(
        IUniswapV2Factory factory,
        IERC20 token0,
        uint256 amountToken0,
        IERC20 token1,
        uint256 amountToken1
    ) public returns (IUniswapV2Pair uniswapVPair) {
        uniswapVPair = IUniswapV2Pair(factory.createPair(address(token0), address(token1)));
        deal(address(token0), address(uniswapVPair), amountToken0);
        deal(address(token1), address(uniswapVPair), amountToken1);
        uniswapVPair.mint(
            Utils.addressFromString("E2EConditionalOrderTest sink address from UniswapV2 liquidity tokens")
        );
    }

    function testE2ESettle() public {
        uint256 startAmountDai = 2_000 ether;
        uint256 startAmountWeth = 1 ether;
        // Deal the AMM reserves to the owner.
        deal(address(DAI), address(owner), startAmountDai);
        deal(address(WETH), address(owner), startAmountWeth);

        vm.startPrank(owner);
        DAI.approve(address(ammFactory), type(uint256).max);
        WETH.approve(address(ammFactory), type(uint256).max);

        // Funds have been allocated.
        assertEq(DAI.balanceOf(owner), startAmountDai);
        assertEq(WETH.balanceOf(owner), startAmountWeth);

        uint256 minTradedToken0 = 0;
        bytes memory priceOracleData = abi.encode(UniswapV2PriceOracle.Data(pair));
        bytes32 appData = keccak256("order app data");
        ConstantProduct amm = ammFactory.create(
            DAI, startAmountDai, WETH, startAmountWeth, minTradedToken0, uniswapV2PriceOracle, priceOracleData, appData
        );
        vm.stopPrank();

        // Funds have been transferred to the AMM.
        assertEq(DAI.balanceOf(owner), 0);
        assertEq(WETH.balanceOf(owner), 0);

        ConstantProduct.TradingParams memory data = ConstantProduct.TradingParams({
            minTradedToken0: minTradedToken0,
            priceOracle: uniswapV2PriceOracle,
            priceOracleData: priceOracleData,
            appData: appData
        });
        IConditionalOrder.ConditionalOrderParams memory params =
            super.createOrder(IConditionalOrder(address(ammFactory)), keccak256("e2e:any salt"), abi.encode(data));
        (GPv2Order.Data memory order, bytes memory sig) =
            ammFactory.getTradeableOrderWithSignature(amm, params, hex"", new bytes32[](0));

        // The trade will be settled against bob.
        deal(address(DAI), bob.addr, startAmountDai);
        deal(address(WETH), bob.addr, startAmountWeth);
        vm.startPrank(bob.addr);
        DAI.approve(address(relayer), type(uint256).max);
        WETH.approve(address(relayer), type(uint256).max);
        vm.stopPrank();

        settle(address(amm), bob, order, sig, hex"");

        uint256 endBalanceDai = DAI.balanceOf(address(amm));
        uint256 endBalanceWeth = WETH.balanceOf(address(amm));
        {
            // Braces to avoid stack too deep.
            uint256 expectedDifferenceDai = 416.666666666666664667 ether;
            uint256 expectedDifferenceWeth = 0.166666666666666666 ether;
            assertEq(startAmountDai + expectedDifferenceDai, endBalanceDai);
            assertEq(startAmountWeth, endBalanceWeth + expectedDifferenceWeth);
            // Explicit price to see that it's reasonable
            assertEq(expectedDifferenceDai / expectedDifferenceWeth, 2_499);
        }

        vm.prank(owner);
        ammFactory.disableTrading(amm);

        vm.prank(owner);
        ammFactory.withdraw(amm, endBalanceDai, endBalanceWeth);

        // Funds have been transferred to the owner.
        assertEq(DAI.balanceOf(owner), endBalanceDai);
        assertEq(WETH.balanceOf(owner), endBalanceWeth);
    }

    function testE2ECustomOrder() public {
        uint256 startAmountDai = 2_000 ether;
        uint256 startAmountWeth = 1 ether;
        // Deal the AMM reserves to the owner.
        deal(address(DAI), address(owner), startAmountDai);
        deal(address(WETH), address(owner), startAmountWeth);

        vm.startPrank(owner);
        DAI.approve(address(ammFactory), type(uint256).max);
        WETH.approve(address(ammFactory), type(uint256).max);

        // Funds have been allocated.
        assertEq(DAI.balanceOf(owner), startAmountDai);
        assertEq(WETH.balanceOf(owner), startAmountWeth);

        uint256 minTradedToken0 = 0;
        bytes memory priceOracleData = abi.encode(UniswapV2PriceOracle.Data(pair));
        bytes32 appData = keccak256("order app data");
        ConstantProduct amm = ammFactory.create(
            DAI, startAmountDai, WETH, startAmountWeth, minTradedToken0, uniswapV2PriceOracle, priceOracleData, appData
        );
        vm.stopPrank();

        // Funds have been transferred to the AMM.
        assertEq(DAI.balanceOf(owner), 0);
        assertEq(WETH.balanceOf(owner), 0);

        ConstantProduct.TradingParams memory data = ConstantProduct.TradingParams({
            minTradedToken0: minTradedToken0,
            priceOracle: uniswapV2PriceOracle,
            priceOracleData: priceOracleData,
            appData: appData
        });
        uint256 sellAmount = 100 ether;
        uint256 buyAmount = 1 ether;

        // The trade will be settled against bob.
        deal(address(DAI), bob.addr, startAmountDai);
        deal(address(WETH), bob.addr, startAmountWeth);
        vm.startPrank(bob.addr);
        DAI.approve(address(relayer), type(uint256).max);
        WETH.approve(address(relayer), type(uint256).max);
        vm.stopPrank();

        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: DAI,
            buyToken: WETH,
            receiver: GPv2Order.RECEIVER_SAME_AS_OWNER,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: uint32(block.timestamp) + 1,
            appData: appData,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: true,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
        bytes memory sig = abi.encode(order, data);

        bytes32 domainSeparator = settlement.domainSeparator();
        // The commit should be part of the settlement for the test to work.
        // This would require us to vendor quite a lot of helper code from
        // composable-cow to include interactions in `settle`. For now, we rely
        // on the fact that Foundry doesn't reset transient storage between
        // calls.
        vm.prank(address(settlement));
        amm.commit(order.hash(domainSeparator));
        settle(address(amm), bob, order, sig, hex"");

        uint256 endBalanceDai = DAI.balanceOf(address(amm));
        uint256 endBalanceWeth = WETH.balanceOf(address(amm));
        assertEq(startAmountDai - sellAmount, endBalanceDai);
        assertEq(startAmountWeth + buyAmount, endBalanceWeth);

        vm.prank(owner);
        ammFactory.disableTrading(amm);

        vm.prank(owner);
        ammFactory.withdraw(amm, endBalanceDai, endBalanceWeth);

        // Funds have been transferred to the owner.
        assertEq(DAI.balanceOf(owner), endBalanceDai);
        assertEq(WETH.balanceOf(owner), endBalanceWeth);
    }
}
