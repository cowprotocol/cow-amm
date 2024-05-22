// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {UniswapV3PriceOracle, IUniswapV3Pool, IERC20} from "src/oracles/UniswapV3PriceOracle.sol";

contract UniswapV3PriceOracleTest is Test {
    address private token0 = makeAddr("X");
    address private token1 = makeAddr("Y");
    address private DEFAULT_PAIR = makeAddr("default token0/token1 pool");
    uint160 private constant sqrtPriceX96 = 3000 * (2 ** 96);
    uint256 private constant price = 3000 ** 2;
    uint8 private constant token0Decimals = 8;
    uint8 private constant token1Decimals = 18;

    UniswapV3PriceOracle internal oracle;
    IUniswapV3Pool internal pool;

    function setUp() public {
        oracle = new UniswapV3PriceOracle();

        pool = IUniswapV3Pool(DEFAULT_PAIR);

        vm.mockCall(address(pool), abi.encodeCall(IUniswapV3Pool.token0, ()), abi.encode(token0));
        vm.mockCall(address(pool), abi.encodeCall(IUniswapV3Pool.token1, ()), abi.encode(token1));
        vm.mockCall(address(token0), abi.encodeCall(IERC20.decimals, ()), abi.encode(token0Decimals));
        vm.mockCall(address(token1), abi.encodeCall(IERC20.decimals, ()), abi.encode(token1Decimals));

        int24 tick = 0;
        uint16 unusedObservationIndex = 0;
        uint16 unusedObservationCardinality = 0;
        uint16 unusedObservationCardinalityNext = 0;
        uint8 unusedFeeProtocol = 0;
        bool unusedUnlocked = true;
        vm.mockCall(
            address(DEFAULT_PAIR),
            abi.encodeCall(IUniswapV3Pool.slot0, ()),
            abi.encode(
                sqrtPriceX96,
                tick,
                unusedObservationIndex,
                unusedObservationCardinality,
                unusedObservationCardinalityNext,
                unusedFeeProtocol,
                unusedUnlocked
            )
        );
    }

    function getDefaultOracleData() internal view returns (UniswapV3PriceOracle.Data memory data) {
        data = UniswapV3PriceOracle.Data(pool);
    }

    function testReturnsExpectedPrice() public {
        (uint256 priceNumerator, uint256 priceDenominator) =
            oracle.getPrice(token0, token1, abi.encode(getDefaultOracleData()));
        assertEq(priceNumerator, price * (10 ** token0Decimals));
        assertEq(priceDenominator, 10 ** token1Decimals);
    }

    function testInvertsPriceIfTokensAreInverted() public {
        (uint256 priceNumerator, uint256 priceDenominator) =
            oracle.getPrice(token1, token0, abi.encode(getDefaultOracleData()));
        assertEq(priceNumerator, 10 ** token1Decimals);
        assertEq(priceDenominator, price * (10 ** token0Decimals));
    }

    function testRevertsIfPairUsesIncorrectToken0() public {
        vm.expectRevert("oracle: invalid token0");
        oracle.getPrice(makeAddr("bad token 0"), token1, abi.encode(getDefaultOracleData()));
    }

    function testRevertsIfPairUsesIncorrectToken1() public {
        vm.expectRevert("oracle: invalid token1");
        oracle.getPrice(token0, makeAddr("bad token 1"), abi.encode(getDefaultOracleData()));
    }

    function testRevertsIfPairUsesIncorrectTokenWhenInverted() public {
        vm.expectRevert("oracle: invalid token0");
        oracle.getPrice(makeAddr("bad token 1"), token0, abi.encode(getDefaultOracleData()));
    }
}
