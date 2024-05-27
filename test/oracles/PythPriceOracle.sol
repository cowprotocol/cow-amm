// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

import {PythPriceOracle, IPyth, IWatchtowerCustomErrors, IConditionalOrder} from "src/oracles/PythPriceOracle.sol";

contract PythPriceOracleTest is Test {
    address private unusedToken = makeAddr("unused token");
    bytes32 private USDCOracle = keccak256("USDC Oracle");
    bytes32 private WETHOracle = keccak256("WETH Oracle");

    PythPriceOracle internal oracle;
    IPyth internal oracleAggregator;
    uint256 private defaultMinOraclePrecision = 5000;
    uint256 private defaultTimeThreshold = 1000;
    uint256 private defaultBackoff = 1;

    uint256 currentTimestamp = 10000;

    function setUp() public {
        oracle = new PythPriceOracle(oracleAggregator);
        vm.warp(currentTimestamp);

        vm.mockCall(
            address(oracleAggregator),
            abi.encodeCall(IPyth.getPriceUnsafe, (USDCOracle)),
            abi.encode(int64(1e8), uint64(1e4), -8, currentTimestamp - 1)
        );
        vm.mockCall(
            address(oracleAggregator),
            abi.encodeCall(IPyth.getPriceUnsafe, (WETHOracle)),
            abi.encode(int64(3000e8), uint64(1e4), -8, currentTimestamp - 1)
        );
    }

    function getDefaultOracleData() internal view returns (PythPriceOracle.Data memory data) {
        data = PythPriceOracle.Data({
            token0Feed: USDCOracle,
            token1Feed: WETHOracle,
            minPrecisionBps: defaultMinOraclePrecision,
            timeThreshold: defaultTimeThreshold,
            backoff: defaultBackoff
        });
    }

    function testReturnsExpectedPrice() public {
        (uint256 priceNumerator, uint256 priceDenominator) =
            oracle.getPrice(unusedToken, unusedToken, abi.encode(getDefaultOracleData()));
        assertEq(priceNumerator, 3000e8);
        assertEq(priceDenominator, 1e8);
    }

    function testReturnsInvertedPrice() public {
        (uint256 priceNumerator, uint256 priceDenominator) = oracle.getPrice(
            unusedToken,
            unusedToken,
            abi.encode(
                PythPriceOracle.Data({
                    token0Feed: WETHOracle,
                    token1Feed: USDCOracle,
                    minPrecisionBps: defaultMinOraclePrecision,
                    timeThreshold: defaultTimeThreshold,
                    backoff: defaultBackoff
                })
            )
        );
        assertEq(priceNumerator, 1e8);
        assertEq(priceDenominator, 3000e8);
    }

    function testNormalizedDecimals() public {
        vm.mockCall(
            address(oracleAggregator),
            abi.encodeCall(IPyth.getPriceUnsafe, (WETHOracle)),
            abi.encode(int64(3000e9), uint64(1e4), -9, currentTimestamp - 1)
        );
        (uint256 priceNumerator, uint256 priceDenominator) =
            oracle.getPrice(unusedToken, unusedToken, abi.encode(getDefaultOracleData()));
        assertEq(priceNumerator, 3000e18);
        assertEq(priceDenominator, 1e18);
    }

    function testRevertsDecimalsAboveLimit() public {
        vm.mockCall(
            address(oracleAggregator),
            abi.encodeCall(IPyth.getPriceUnsafe, (USDCOracle)),
            abi.encode(int64(1e18), uint64(1e6), -19, currentTimestamp - 1)
        );
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "unsupported decimals"));
        oracle.getPrice(unusedToken, unusedToken, abi.encode(getDefaultOracleData()));
    }

    function testRevertsNegativeDecimalsLimit() public {
        vm.mockCall(
            address(oracleAggregator),
            abi.encodeCall(IPyth.getPriceUnsafe, (USDCOracle)),
            abi.encode(int64(1e18), uint64(1e6), 1, currentTimestamp - 1)
        );
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "unsupported decimals"));
        oracle.getPrice(unusedToken, unusedToken, abi.encode(getDefaultOracleData()));
    }

    function testRevertsIfOracleIsStale() public {
        vm.warp(currentTimestamp + defaultTimeThreshold + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWatchtowerCustomErrors.PollTryAtEpoch.selector, block.timestamp + defaultBackoff, "stale oracle"
            )
        );
        oracle.getPrice(unusedToken, unusedToken, abi.encode(getDefaultOracleData()));
    }

    function testRevertsIfPriceIsNegative() public {
        vm.mockCall(
            address(oracleAggregator),
            abi.encodeCall(IPyth.getPriceUnsafe, (USDCOracle)),
            abi.encode(int64(-1e8), uint64(1e6), -6, currentTimestamp - 1)
        );
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "negative price"));
        oracle.getPrice(unusedToken, unusedToken, abi.encode(getDefaultOracleData()));
    }

    function testRevertsIfOracleIsImprecise() public {
        vm.mockCall(
            address(oracleAggregator),
            abi.encodeCall(IPyth.getPriceUnsafe, (USDCOracle)),
            abi.encode(int64(1e8), uint64(6e7), -6, currentTimestamp - 1)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IWatchtowerCustomErrors.PollTryAtEpoch.selector, block.timestamp + defaultBackoff, "imprecise oracle"
            )
        );
        oracle.getPrice(unusedToken, unusedToken, abi.encode(getDefaultOracleData()));
    }
}
