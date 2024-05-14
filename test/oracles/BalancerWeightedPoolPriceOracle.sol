// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin/contracts/interfaces/IERC20.sol";

import {
    BalancerWeightedPoolPriceOracle,
    IVault,
    IWeightedPool,
    IConditionalOrder
} from "src/oracles/BalancerWeightedPoolPriceOracle.sol";

contract BalancerWeightedPoolPriceOracleTest is Test {
    IERC20 private USDC = IERC20(makeAddr("USDC"));
    IERC20 private WETH = IERC20(makeAddr("WETH"));
    // Technically, the first 20 bytes should be the pool address.
    // However, this property is not relied on by the Balancer price oracle.
    bytes32 private DEFAULT_POOL_ID = keccak256("Default Balancer pool id");
    IWeightedPool internal pool = IWeightedPool(makeAddr("Balancer pool"));
    IVault internal balancerVault = IVault(makeAddr("Balancer vault"));
    BalancerWeightedPoolPriceOracle internal oracle;

    function setUp() public {
        oracle = new BalancerWeightedPoolPriceOracle(balancerVault);
    }

    function testRevertsIfPoolNotRegistered() public {
        vm.mockCallRevert(
            address(balancerVault), abi.encodeCall(IVault.getPool, (DEFAULT_POOL_ID)), abi.encode("pool not registered")
        );

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "invalid pool id"));
        oracle.getPrice(address(USDC), address(WETH), getDefaultTradingParams());
    }

    function testRevertsIfNoTokensAvailable() public {
        registerPoolOnVault();
        vm.mockCallRevert(
            address(balancerVault),
            abi.encodeCall(IVault.getPoolTokens, (DEFAULT_POOL_ID)),
            abi.encode("Test with no tokens available")
        );

        // There is no custom revert message because we already checked that the
        // pool is registered. We don't expect this function to revert at this
        // point.
        vm.expectRevert();
        oracle.getPrice(address(USDC), address(WETH), getDefaultTradingParams());
    }

    function testRevertsIfNoWeightsAvailable() public {
        registerPoolOnVault();
        setUpDefaultBalancerPool(new IERC20[](0), new uint256[](0), new uint256[](0));
        vm.mockCallRevert(
            address(pool),
            abi.encodeCall(IWeightedPool.getNormalizedWeights, ()),
            abi.encode("Called unexpected function on mock vault")
        );

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "not a weighted pool"));
        oracle.getPrice(address(USDC), address(WETH), getDefaultTradingParams());
    }

    function testRevertsIfToken0IsNotPartOfThePool() public {
        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory balances = new uint256[](1);
        uint256[] memory weights = new uint256[](1);
        tokens[0] = WETH;
        balances[0] = 1337;
        weights[0] = 42;
        setUpDefaultBalancerPool(tokens, balances, weights);

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "pool does not trade token0"));
        oracle.getPrice(address(USDC), address(WETH), getDefaultTradingParams());
    }

    function testRevertsIfToken1IsNotPartOfThePool() public {
        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory balances = new uint256[](1);
        uint256[] memory weights = new uint256[](1);
        tokens[0] = USDC;
        balances[0] = 1337;
        weights[0] = 42;
        setUpDefaultBalancerPool(tokens, balances, weights);

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "pool does not trade token1"));
        oracle.getPrice(address(USDC), address(WETH), getDefaultTradingParams());
    }

    function testComputesExpectedPriceWithUniformWeights() public {
        IERC20[] memory tokens = new IERC20[](2);
        uint256[] memory balances = new uint256[](2);
        uint256[] memory weights = new uint256[](2);
        tokens[0] = USDC;
        balances[0] = 200_000 ether;
        weights[0] = 0.5 ether;
        tokens[1] = WETH;
        balances[1] = 100 ether;
        weights[1] = 0.5 ether;
        setUpDefaultBalancerPool(tokens, balances, weights);

        (uint256 num, uint256 den) = oracle.getPrice(address(USDC), address(WETH), getDefaultTradingParams());
        assertEq(num / den, 2000);
    }

    function testComputesExpectedPriceWithUniformWeightsInvertedOrder() public {
        IERC20[] memory tokens = new IERC20[](2);
        uint256[] memory balances = new uint256[](2);
        uint256[] memory weights = new uint256[](2);
        tokens[0] = USDC;
        balances[0] = 200_000 ether;
        weights[0] = 0.5 ether;
        tokens[1] = WETH;
        balances[1] = 100 ether;
        weights[1] = 0.5 ether;
        setUpDefaultBalancerPool(tokens, balances, weights);

        (uint256 num, uint256 den) = oracle.getPrice(address(WETH), address(USDC), getDefaultTradingParams());
        // Inverting the fraction to still get an integer price
        assertEq(den / num, 2000);
    }

    function testRobustForMultipleTokens() public {
        IERC20[] memory tokens = new IERC20[](4);
        uint256[] memory balances = new uint256[](4);
        uint256[] memory weights = new uint256[](4);
        tokens[0] = IERC20(makeAddr("some other token"));
        balances[0] = 1337;
        weights[0] = 0.25 ether;
        tokens[1] = USDC;
        balances[1] = 200_000 ether;
        weights[1] = 0.25 ether;
        tokens[2] = IERC20(makeAddr("again some other token"));
        balances[2] = 42;
        weights[2] = 0.25 ether;
        tokens[3] = WETH;
        balances[3] = 100 ether;
        weights[3] = 0.25 ether;
        setUpDefaultBalancerPool(tokens, balances, weights);

        (uint256 num, uint256 den) = oracle.getPrice(address(USDC), address(WETH), getDefaultTradingParams());
        assertEq(num / den, 2000);
    }

    function testPriceWithNonUniformWeights() public {
        IERC20[] memory tokens = new IERC20[](2);
        uint256[] memory balances = new uint256[](2);
        uint256[] memory weights = new uint256[](2);
        uint256 weightAdjustment = 4;
        tokens[0] = USDC;
        balances[0] = 200_000 ether * weightAdjustment;
        weights[0] = 0.8 ether;
        tokens[1] = WETH;
        balances[1] = 100 ether;
        weights[1] = 0.2 ether;
        setUpDefaultBalancerPool(tokens, balances, weights);

        (uint256 num, uint256 den) = oracle.getPrice(address(USDC), address(WETH), getDefaultTradingParams());

        assertEq(num / den, 2000);
    }

    function testPriceFromActualCowWethPoolValues() public {
        // Test with COW/WETH pool 0xde8c195aa41c11a0c4787372defbbddaa31306d2000200000000000000000181
        // Values from Etherscan
        IERC20 COW = IERC20(makeAddr("COW"));
        IERC20[] memory tokens = new IERC20[](2);
        uint256[] memory balances = new uint256[](2);
        uint256[] memory weights = new uint256[](2);
        tokens[0] = WETH;
        balances[0] = 241480622098035103541;
        weights[0] = 500000000000000000;
        tokens[1] = COW;
        balances[1] = 1489620988536903135970336;
        weights[1] = 500000000000000000;
        setUpDefaultBalancerPool(tokens, balances, weights);

        (uint256 num, uint256 den) = oracle.getPrice(address(COW), address(WETH), getDefaultTradingParams());

        assertEq(num / den, 6168);
        // The price is close to the last onchain trade involving this pool:
        // https://etherscan.io/tx/0x0bc57c87344b8908de3799c244559d177b6b74fc332391aa411a64a2f06d2461
    }

    function testPriceFromActualComplexPoolValues() public {
        // Test with Balancer 50KNC-25WETH-25USDC 0x6f0ed6f346007563d3266de350d174a831bde0ca0001000000000000000005db
        // Values from Etherscan
        IERC20 KNC = IERC20(makeAddr("KNC"));
        IERC20[] memory tokens = new IERC20[](3);
        uint256[] memory balances = new uint256[](3);
        uint256[] memory weights = new uint256[](3);
        tokens[0] = USDC;
        balances[0] = 1155058399278;
        weights[0] = 250000000000000000;
        tokens[1] = WETH;
        balances[1] = 432325169965725108980;
        weights[1] = 250000000000000000;
        tokens[2] = KNC;
        balances[2] = 3648449922658503230449855;
        weights[2] = 500000000000000000;
        setUpDefaultBalancerPool(tokens, balances, weights);

        uint256 decimalAdjustment = 10 ** 18 / 10 ** 6;
        (uint256 num1, uint256 den1) = oracle.getPrice(address(USDC), address(WETH), getDefaultTradingParams());
        assertEq(num1 * decimalAdjustment / den1, 2671);
        // The price is close to the last onchain trade involving this pool and tokens:
        // https://etherscan.io/tx/0x30a83c1be9a335b3e62467c4da2eb82700a331730cc66f4dc2efb6b20d229ea7

        (uint256 num2, uint256 den2) = oracle.getPrice(address(KNC), address(USDC), getDefaultTradingParams());
        // Multiply by 1000 because the price is ~1.579 and rounding would cause
        // the decimals to be truncated.
        assertEq(1000 * num2 / (den2 * decimalAdjustment), 1579);
        // The price is close to the last onchain trade involving this pool and tokens:
        // https://etherscan.io/tx/0xf5e33f63110a3ea4d8fd2a8c024ea5d3e382032e3443def987f2b85ac43853c6
    }

    function registerPoolOnVault() internal {
        vm.mockCall(
            address(balancerVault),
            abi.encodeCall(IVault.getPool, (DEFAULT_POOL_ID)),
            abi.encode(address(pool), IVault.PoolSpecialization.GENERAL)
        );
    }

    function registerTokensAndBalancesOnVault(IERC20[] memory tokens, uint256[] memory balances) internal {
        uint256 lastChangeBlock = 1337;
        vm.mockCall(
            address(balancerVault),
            abi.encodeCall(IVault.getPoolTokens, (DEFAULT_POOL_ID)),
            abi.encode(tokens, balances, lastChangeBlock)
        );
    }

    function setUpDefaultBalancerPool(IERC20[] memory tokens, uint256[] memory balances, uint256[] memory weights)
        internal
    {
        registerPoolOnVault();
        registerTokensAndBalancesOnVault(tokens, balances);
        vm.mockCallRevert(address(balancerVault), hex"", abi.encode("Called unexpected function on mock vault"));

        vm.mockCall(address(pool), abi.encodeCall(IWeightedPool.getNormalizedWeights, ()), abi.encode(weights));
        vm.mockCallRevert(address(pool), hex"", abi.encode("Called unexpected function on mock pool"));
    }

    function getDefaultTradingParams() internal view returns (bytes memory data) {
        return abi.encode(BalancerWeightedPoolPriceOracle.Data(DEFAULT_POOL_ID));
    }
}
