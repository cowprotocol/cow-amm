// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {BaseComposableCoWTest} from "lib/composable-cow/test/ComposableCoW.base.t.sol";

import {Utils} from "../libraries/Utils.sol";
import {ConstantProduct, GPv2Order, IERC20} from "../../src/ConstantProduct.sol";
import {UniswapV2PriceOracle, IUniswapV2Pair} from "../../src/oracles/UniswapV2PriceOracle.sol";

abstract contract ConstantProductTestHarness is BaseComposableCoWTest {
    address internal orderOwner = Utils.addressFromString("order owner");
    address private USDC = Utils.addressFromString("USDC");
    address private WETH = Utils.addressFromString("WETH");
    address private DEFAULT_PAIR = Utils.addressFromString("default USDC/WETH pair");
    address private DEFAULT_RECEIVER = Utils.addressFromString("default receiver");
    bytes32 private DEFAULT_APPDATA = keccak256(bytes("unit test"));
    bytes32 private DEFAULT_COMMITMENT = keccak256(bytes("order hash"));

    address internal solutionSettler = Utils.addressFromString("settlement contract");
    ConstantProduct internal constantProduct;
    UniswapV2PriceOracle internal uniswapV2PriceOracle;

    function setUp() public virtual override(BaseComposableCoWTest) {
        super.setUp();

        constantProduct = new ConstantProduct(solutionSettler);
        uniswapV2PriceOracle = new UniswapV2PriceOracle();
    }

    function setUpDefaultPair() internal {
        vm.mockCall(DEFAULT_PAIR, abi.encodeWithSelector(IUniswapV2Pair.token0.selector), abi.encode(USDC));
        vm.mockCall(DEFAULT_PAIR, abi.encodeWithSelector(IUniswapV2Pair.token1.selector), abi.encode(WETH));
        // Reverts for everything else
        vm.mockCallRevert(DEFAULT_PAIR, hex"", abi.encode("Called unexpected function on mock pair"));
        IUniswapV2Pair pair = IUniswapV2Pair(DEFAULT_PAIR);
        require(pair.token0() != pair.token1(), "Pair setup failed: should use distinct tokens");
    }

    function getDefaultData() internal view returns (ConstantProduct.Data memory) {
        return ConstantProduct.Data(
            IERC20(USDC),
            IERC20(WETH),
            0,
            uniswapV2PriceOracle,
            abi.encode(UniswapV2PriceOracle.Data(IUniswapV2Pair(DEFAULT_PAIR))),
            DEFAULT_APPDATA
        );
    }

    function setUpDefaultData() internal returns (ConstantProduct.Data memory) {
        setUpDefaultPair();
        return getDefaultData();
    }

    function setUpDefaultCommitment(address owner) internal {
        vm.prank(solutionSettler);
        constantProduct.commit(owner, DEFAULT_COMMITMENT);
    }

    function setUpDefaultReserves(address owner) internal {
        setUpDefaultWithReserves(owner, 1337, 1337);
    }

    function setUpDefaultWithReserves(address owner, uint256 amount0, uint256 amount1) internal {
        ConstantProduct.Data memory defaultData = setUpDefaultData();
        UniswapV2PriceOracle.Data memory oracleData =
            abi.decode(defaultData.priceOracleData, (UniswapV2PriceOracle.Data));

        vm.mockCall(
            oracleData.referencePair.token0(),
            abi.encodeWithSelector(IERC20.balanceOf.selector, owner),
            abi.encode(amount0)
        );
        vm.mockCall(
            oracleData.referencePair.token1(),
            abi.encodeWithSelector(IERC20.balanceOf.selector, owner),
            abi.encode(amount1)
        );
    }

    function setUpDefaultReferencePairReserves(uint256 amount0, uint256 amount1) public {
        uint32 unusedTimestamp = 31337;
        vm.mockCall(
            address(DEFAULT_PAIR),
            abi.encodeWithSelector(IUniswapV2Pair.getReserves.selector),
            abi.encode(amount0, amount1, unusedTimestamp)
        );
    }

    // This function calls `getTradeableOrder` while filling all unused
    // parameters with arbitrary data.
    function getTradeableOrderUncheckedWrapper(address owner, ConstantProduct.Data memory staticInput)
        internal
        view
        returns (GPv2Order.Data memory order)
    {
        order = constantProduct.getTradeableOrder(
            owner,
            Utils.addressFromString("sender"),
            keccak256(bytes("context")),
            abi.encode(staticInput),
            bytes("offchain input")
        );
    }

    // This function calls `getTradeableOrder` while filling all unused
    // parameters with arbitrary data. It also immediately checks that the order
    // is valid.
    function getTradeableOrderWrapper(address owner, ConstantProduct.Data memory staticInput)
        internal
        view
        returns (GPv2Order.Data memory order)
    {
        order = getTradeableOrderUncheckedWrapper(owner, staticInput);
        verifyWrapper(owner, staticInput, order);
    }

    // This function calls `verify` while filling all unused parameters with
    // arbitrary data and the order hash with the default commitment.
    function verifyWrapper(address owner, ConstantProduct.Data memory staticInput, GPv2Order.Data memory order)
        internal
        view
    {
        verifyWrapper(owner, DEFAULT_COMMITMENT, staticInput, order);
    }

    function verifyWrapper(
        address owner,
        bytes32 orderHash,
        ConstantProduct.Data memory staticInput,
        GPv2Order.Data memory order
    ) internal view {
        constantProduct.verify(
            owner,
            Utils.addressFromString("sender"),
            orderHash,
            keccak256(bytes("domain separator")),
            keccak256(bytes("context")),
            abi.encode(staticInput),
            bytes("offchain input"),
            order
        );
    }

    function getDefaultOrder() internal view returns (GPv2Order.Data memory) {
        ConstantProduct.Data memory data = getDefaultData();

        return GPv2Order.Data(
            IERC20(USDC), // IERC20 sellToken;
            IERC20(WETH), // IERC20 buyToken;
            GPv2Order.RECEIVER_SAME_AS_OWNER, // address receiver;
            0, // uint256 sellAmount;
            0, // uint256 buyAmount;
            uint32(block.timestamp) + constantProduct.MAX_ORDER_DURATION() / 2, // uint32 validTo;
            data.appData, // bytes32 appData;
            0, // uint256 feeAmount;
            GPv2Order.KIND_SELL, // bytes32 kind;
            true, // bool partiallyFillable;
            GPv2Order.BALANCE_ERC20, // bytes32 sellTokenBalance;
            GPv2Order.BALANCE_ERC20 // bytes32 buyTokenBalance;
        );
    }
}
