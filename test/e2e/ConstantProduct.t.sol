// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {
    BaseComposableCoWTest, Safe, TestAccount, TestAccountLib
} from "lib/composable-cow/test/ComposableCoW.base.t.sol";

import {ConstantProduct, IConditionalOrder, GPv2Order, IERC20, ISettlement} from "src/ConstantProduct.sol";
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
    ConstantProduct constantProduct;
    UniswapV2PriceOracle uniswapV2PriceOracle;
    bytes32 domainSeparator;

    function setUp() public virtual override(BaseComposableCoWTest) {
        super.setUp();
        DAI = token0;
        WETH = token1;
        constantProduct = new ConstantProduct(ISettlement(address(settlement)), DAI, WETH);
        uniswapV2PriceOracle = new UniswapV2PriceOracle();
        domainSeparator = composableCow.domainSeparator();
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
        (Safe amm, TestAccount[] memory owners) = deployAmmSafe();

        ConstantProduct.Data memory data = ConstantProduct.Data(
            0, uniswapV2PriceOracle, abi.encode(UniswapV2PriceOracle.Data(pair)), keccak256("order app data")
        );
        IConditionalOrder.ConditionalOrderParams memory params =
            super.createOrder(constantProduct, keccak256("any salt"), abi.encode(data));
        // Create the conditional order.
        _create(address(amm), params, true);

        uint256 startAmountDai = 2_000 ether;
        uint256 startAmountWeth = 1 ether;
        // Deal the AMM reserves to the safe.
        deal(address(DAI), address(amm), startAmountDai);
        deal(address(WETH), address(amm), startAmountWeth);
        // Authorise the vault relayer to pull the tokens from the safe.
        amm.execCall(address(DAI), abi.encodeCall(DAI.approve, (address(relayer), type(uint256).max)), owners);
        amm.execCall(address(WETH), abi.encodeCall(WETH.approve, (address(relayer), type(uint256).max)), owners);

        (GPv2Order.Data memory order, bytes memory sig) =
            composableCow.getTradeableOrderWithSignature(address(amm), params, abi.encode(safe2), new bytes32[](0));

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
    }

    function deployAmmSafe() internal returns (Safe amm, TestAccount[] memory owners) {
        owners = new TestAccount[](2);
        owners[0] = TestAccountLib.createTestAccount("owner 1");
        owners[1] = TestAccountLib.createTestAccount("owner 2");

        // The safe already sets the extensible fallback handler during its
        // deployment.
        amm = SafeHelper.createSafe(factory, singleton, owners, 1, address(eHandler));
        amm.execCall(address(amm), abi.encodeCall(eHandler.setDomainVerifier, (domainSeparator, composableCow)), owners);
    }
}
