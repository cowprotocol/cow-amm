// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {BaseComposableCoWTest} from "lib/composable-cow/test/ComposableCoW.base.t.sol";

import {ConstantProduct, GPv2Order, IERC20} from "src/ConstantProduct.sol";
import {UniswapV2PriceOracle, IUniswapV2Pair} from "src/oracles/UniswapV2PriceOracle.sol";
import {ISettlement} from "src/interfaces/ISettlement.sol";

abstract contract ConstantProductTestHarness is BaseComposableCoWTest {
    using GPv2Order for GPv2Order.Data;

    struct SignatureData {
        GPv2Order.Data order;
        bytes32 orderHash;
        bytes signature;
    }

    address internal vaultRelayer = makeAddr("vault relayer");
    address private USDC = makeAddr("USDC");
    address private WETH = makeAddr("WETH");
    address private DEFAULT_PAIR = makeAddr("default USDC/WETH pair");
    address private DEFAULT_RECEIVER = makeAddr("default receiver");
    address private DEFAULT_SOLUTION_SETTLER = makeAddr("settlement contract");
    bytes32 private DEFAULT_APPDATA = keccak256(bytes("unit test"));
    bytes32 private DEFAULT_COMMITMENT = keccak256(bytes("order hash"));
    bytes32 private DEFAULT_DOMAIN_SEPARATOR = keccak256(bytes("domain separator hash"));

    ISettlement internal solutionSettler = ISettlement(DEFAULT_SOLUTION_SETTLER);
    ConstantProduct internal constantProduct;
    UniswapV2PriceOracle internal uniswapV2PriceOracle;

    function setUp() public virtual override(BaseComposableCoWTest) {
        super.setUp();
        address constantProductAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        setUpSolutionSettler();
        setUpAmmDeployment(constantProductAddress);
        constantProduct = new ConstantProduct(solutionSettler, IERC20(USDC), IERC20(WETH));
        uniswapV2PriceOracle = new UniswapV2PriceOracle();
    }

    function setUpSolutionSettler() internal {
        vm.mockCall(
            DEFAULT_SOLUTION_SETTLER,
            abi.encodeCall(ISettlement.domainSeparator, ()),
            abi.encode(DEFAULT_DOMAIN_SEPARATOR)
        );
        vm.mockCall(DEFAULT_SOLUTION_SETTLER, abi.encodeCall(ISettlement.vaultRelayer, ()), abi.encode(vaultRelayer));
        vm.mockCallRevert(
            DEFAULT_SOLUTION_SETTLER, hex"", abi.encode("Called unexpected function on mock settlement contract")
        );
    }

    function setUpDefaultPair() internal {
        vm.mockCall(DEFAULT_PAIR, abi.encodeCall(IUniswapV2Pair.token0, ()), abi.encode(USDC));
        vm.mockCall(DEFAULT_PAIR, abi.encodeCall(IUniswapV2Pair.token1, ()), abi.encode(WETH));
        // Reverts for everything else
        vm.mockCallRevert(DEFAULT_PAIR, hex"", abi.encode("Called unexpected function on mock pair"));
        IUniswapV2Pair pair = IUniswapV2Pair(DEFAULT_PAIR);
        require(pair.token0() != pair.token1(), "Pair setup failed: should use distinct tokens");
    }

    function setUpDefaultCommitment() internal {
        vm.prank(address(solutionSettler));
        constantProduct.commit(DEFAULT_COMMITMENT);
    }

    function setUpDefaultReserves(address owner) internal {
        setUpDefaultWithReserves(owner, 1337, 1337);
    }

    function setUpDefaultWithReserves(address owner, uint256 amount0, uint256 amount1) internal {
        vm.mockCall(USDC, abi.encodeCall(IERC20.balanceOf, (owner)), abi.encode(amount0));
        vm.mockCall(WETH, abi.encodeCall(IERC20.balanceOf, (owner)), abi.encode(amount1));
    }

    function setUpDefaultReferencePairReserves(uint256 amount0, uint256 amount1) public {
        uint32 unusedTimestamp = 31337;
        vm.mockCall(
            address(DEFAULT_PAIR),
            abi.encodeCall(IUniswapV2Pair.getReserves, ()),
            abi.encode(amount0, amount1, unusedTimestamp)
        );
    }

    function defaultSignatureAndHashes() internal view returns (SignatureData memory out) {
        GPv2Order.Data memory order = getDefaultOrder();
        bytes32 orderHash = order.hash(solutionSettler.domainSeparator());
        bytes memory signature = abi.encode(order);
        out = SignatureData(order, orderHash, signature);
    }

    function getDefaultOrder() internal view returns (GPv2Order.Data memory) {
        return GPv2Order.Data(
            IERC20(USDC), // IERC20 sellToken;
            IERC20(WETH), // IERC20 buyToken;
            GPv2Order.RECEIVER_SAME_AS_OWNER, // address receiver;
            0, // uint256 sellAmount;
            0, // uint256 buyAmount;
            uint32(block.timestamp) + constantProduct.MAX_ORDER_DURATION() / 2, // uint32 validTo;
            constantProduct.APP_DATA(), // bytes32 appData;
            0, // uint256 feeAmount;
            GPv2Order.KIND_SELL, // bytes32 kind;
            true, // bool partiallyFillable;
            GPv2Order.BALANCE_ERC20, // bytes32 sellTokenBalance;
            GPv2Order.BALANCE_ERC20 // bytes32 buyTokenBalance;
        );
    }

    function setUpAmmDeployment(address constantProductAddress) internal {
        setUpTokenForDeployment(IERC20(USDC), constantProductAddress, address(this));
        setUpTokenForDeployment(IERC20(WETH), constantProductAddress, address(this));
    }

    function setUpTokenForDeployment(IERC20 token, address constantProductAddress, address owner) internal {
        mockSafeApprove(token, constantProductAddress, solutionSettler.vaultRelayer());
        mockSafeApprove(token, constantProductAddress, owner);
    }

    function mockSafeApprove(IERC20 token, address owner, address spender) internal {
        mockZeroAllowance(token, owner, spender);
        mockApprove(token, spender);
    }

    function mockApprove(IERC20 token, address spender) internal {
        vm.mockCall(address(token), abi.encodeCall(IERC20.approve, (spender, type(uint256).max)), abi.encode(true));
    }

    function mockZeroAllowance(IERC20 token, address owner, address spender) internal {
        vm.mockCall(address(token), abi.encodeCall(IERC20.allowance, (owner, spender)), abi.encode(0));
    }
}
