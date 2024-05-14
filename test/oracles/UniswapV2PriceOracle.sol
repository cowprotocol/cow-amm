// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {UniswapV2PriceOracle, IUniswapV2Pair} from "src/oracles/UniswapV2PriceOracle.sol";

contract UniswapV2PriceOracleTest is Test {
    address private USDC = makeAddr("USDC");
    address private WETH = makeAddr("WETH");
    address private DEFAULT_PAIR = makeAddr("default USDC/WETH pair");
    uint128 private constant reserve0 = 1337;
    uint128 private constant reserve1 = 31337;

    UniswapV2PriceOracle internal oracle;
    IUniswapV2Pair internal pair;

    function setUp() public {
        oracle = new UniswapV2PriceOracle();

        pair = IUniswapV2Pair(DEFAULT_PAIR);

        vm.mockCall(address(pair), abi.encodeCall(IUniswapV2Pair.token0, ()), abi.encode(USDC));
        vm.mockCall(address(pair), abi.encodeCall(IUniswapV2Pair.token1, ()), abi.encode(WETH));
        uint32 unusedTimestamp = 31337;
        vm.mockCall(
            address(DEFAULT_PAIR),
            abi.encodeCall(IUniswapV2Pair.getReserves, ()),
            abi.encode(reserve0, reserve1, unusedTimestamp)
        );
    }

    function getDefaultOracleData() internal view returns (UniswapV2PriceOracle.Data memory data) {
        data = UniswapV2PriceOracle.Data(pair);
    }

    function testReturnsExpectedPrice() public {
        (uint256 priceNumerator, uint256 priceDenominator) =
            oracle.getPrice(USDC, WETH, abi.encode(getDefaultOracleData()));
        assertEq(priceNumerator, reserve0);
        assertEq(priceDenominator, reserve1);
    }

    function testInvertsPriceIfTokensAreInverted() public {
        (uint256 priceNumerator, uint256 priceDenominator) =
            oracle.getPrice(WETH, USDC, abi.encode(getDefaultOracleData()));
        assertEq(priceNumerator, reserve1);
        assertEq(priceDenominator, reserve0);
    }

    function testRevertsIfPairUsesIncorrectToken0() public {
        vm.expectRevert("oracle: invalid token0");
        oracle.getPrice(makeAddr("bad token 0"), WETH, abi.encode(getDefaultOracleData()));
    }

    function testRevertsIfPairUsesIncorrectToken1() public {
        vm.expectRevert("oracle: invalid token1");
        oracle.getPrice(USDC, makeAddr("bad token 1"), abi.encode(getDefaultOracleData()));
    }

    function testRevertsIfPairUsesIncorrectTokenWhenInverted() public {
        vm.expectRevert("oracle: invalid token0");
        oracle.getPrice(makeAddr("bad token 1"), USDC, abi.encode(getDefaultOracleData()));
    }
}
