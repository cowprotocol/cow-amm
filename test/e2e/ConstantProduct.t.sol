// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {BaseComposableCoWTest, Safe, TestAccount} from "lib/composable-cow/test/ComposableCoW.base.t.sol";

import {ConstantProduct, IERC20, GPv2Order, ISettlement} from "src/ConstantProduct.sol";
import {ConstantProductFactory, IConditionalOrder} from "src/ConstantProductFactory.sol";
import {UniswapV2PriceOracle, IUniswapV2Pair} from "src/oracles/UniswapV2PriceOracle.sol";
import {Utils} from "test/libraries/Utils.sol";
import {TestAccountHelper} from "test/libraries/TestAccountHelper.sol";
import {UniswapV2Helper, IUniswapV2Factory} from "test/libraries/UniswapV2Helper.sol";
import {SafeHelper} from "test/libraries/SafeHelper.sol";

contract E2EConditionalOrderTest is BaseComposableCoWTest {
    using TestAccountHelper for TestAccount[];
    using UniswapV2Helper for IUniswapV2Factory;
    using SafeHelper for Safe;

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
        ConstantProduct.TradingParams memory tradingParams = ConstantProduct.TradingParams({
            minTradedToken0: 0,
            priceOracle: uniswapV2PriceOracle,
            priceOracleData: abi.encode(UniswapV2PriceOracle.Data(pair)),
            appData: keccak256("order app data")
        });
        IConditionalOrder.ConditionalOrderParams memory params = IConditionalOrder.ConditionalOrderParams({
            handler: IConditionalOrder(address(ammFactory)),
            salt: keccak256("e2e:any salt"),
            staticInput: abi.encode(tradingParams)
        });
        ConstantProduct amm = new ConstantProduct(ISettlement(address(settlement)), DAI, WETH);

        uint256 startAmountDai = 2_000 ether;
        uint256 startAmountWeth = 1 ether;
        // Deal the AMM reserves to the safe.
        deal(address(DAI), address(amm), startAmountDai);
        deal(address(WETH), address(amm), startAmountWeth);

        amm.enableTrading(tradingParams);

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
        uint256 expectedDifferenceDai = 416.666666666666664667 ether;
        uint256 expectedDifferenceWeth = 0.166666666666666666 ether;
        assertEq(startAmountDai + expectedDifferenceDai, endBalanceDai);
        assertEq(startAmountWeth, endBalanceWeth + expectedDifferenceWeth);
        // Explicit price to see that it's reasonable
        assertEq(expectedDifferenceDai / expectedDifferenceWeth, 2_499);

        amm.disableTrading();
    }
}
