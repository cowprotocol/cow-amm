// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test, console2} from "forge-std/Test.sol";

import {
    ChainlinkPriceOracle,
    AggregatorV3Interface,
    IWatchtowerCustomErrors,
    IConditionalOrder
} from "src/oracles/ChainlinkPriceOracle.sol";

import {Utils} from "test/libraries/Utils.sol";

contract ChainlinkPriceOracleTest is Test {
    address private USDC = Utils.addressFromString("USDC");
    address private WETH = Utils.addressFromString("WETH");
    address private AMPL = Utils.addressFromString("AMPL");
    address private USDCOracle = Utils.addressFromString("USDC Oracle");
    address private WETHOracle = Utils.addressFromString("WETH Oracle");
    address private AMPLOracle = Utils.addressFromString("AMPL Oracle");

    ChainlinkPriceOracle internal oracle;

    uint80 unusedRoundId = 69;
    uint256 unusedStartedAt = 420;
    uint256 updatedAt = 31336;
    uint80 unusedAnsweredInRound = 70;

    function setUp() public {
        oracle = new ChainlinkPriceOracle();
        vm.warp(31337);

        vm.mockCall(USDCOracle, abi.encodeCall(AggregatorV3Interface.decimals, ()), abi.encode(uint8(8)));
        vm.mockCall(WETHOracle, abi.encodeCall(AggregatorV3Interface.decimals, ()), abi.encode(uint8(8)));
        vm.mockCall(AMPLOracle, abi.encodeCall(AggregatorV3Interface.decimals, ()), abi.encode(uint8(18)));
        vm.mockCall(
            USDCOracle,
            abi.encodeCall(AggregatorV3Interface.latestRoundData, ()),
            abi.encode(
                unusedRoundId,
                int256(1e8), // 1.00 with 8 decimals
                unusedStartedAt,
                updatedAt,
                unusedAnsweredInRound
            )
        );
        vm.mockCall(
            WETHOracle,
            abi.encodeCall(AggregatorV3Interface.latestRoundData, ()),
            abi.encode(unusedRoundId, int256(1000e8), unusedStartedAt, updatedAt, unusedAnsweredInRound)
        );
        vm.mockCall(
            AMPLOracle,
            abi.encodeCall(AggregatorV3Interface.latestRoundData, ()),
            abi.encode(unusedRoundId, int256(1.1e18), unusedStartedAt, updatedAt, unusedAnsweredInRound)
        );
    }

    function getDefaultOracleData() internal view returns (ChainlinkPriceOracle.Data memory data) {
        data = ChainlinkPriceOracle.Data({
            token0Feed: USDCOracle,
            token1Feed: WETHOracle,
            timeThreshold: 1 days,
            backoff: 1 days
        });
    }

    function testReturnsExpectedPrice() public {
        (uint256 priceNumerator, uint256 priceDenominator) =
            oracle.getPrice(USDC, WETH, abi.encode(getDefaultOracleData()));
        assertEq(priceNumerator, 1000e8);
        assertEq(priceDenominator, 1e8);
    }

    function testReturnsInvertedPrice() public {
        (uint256 priceNumerator, uint256 priceDenominator) =
            oracle.getPrice(WETH, USDC, abi.encode(ChainlinkPriceOracle.Data(WETHOracle, USDCOracle, 1 days, 1 days)));
        assertEq(priceNumerator, 1e8);
        assertEq(priceDenominator, 1000e8);
    }

    function testNormalizedDecimals() public {
        (uint256 priceNumerator, uint256 priceDenominator) =
            oracle.getPrice(USDC, AMPL, abi.encode(ChainlinkPriceOracle.Data(USDCOracle, AMPLOracle, 1 days, 1 days)));
        assertEq(priceNumerator, 1.1e18);
        assertEq(priceDenominator, 1e18);
    }

    function testRevertsUnsupportedDecimals() public {
        address badToken = Utils.addressFromString("bad token");
        address badOracle = Utils.addressFromString("bad oracle");
        vm.mockCall(badOracle, abi.encodeCall(AggregatorV3Interface.decimals, ()), abi.encode(uint8(19)));
        vm.mockCall(
            badOracle,
            abi.encodeCall(AggregatorV3Interface.latestRoundData, ()),
            abi.encode(unusedRoundId, int256(1.1e18), unusedStartedAt, updatedAt, unusedAnsweredInRound)
        );
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "Unsupported decimals (>18)"));
        oracle.getPrice(USDC, badToken, abi.encode(ChainlinkPriceOracle.Data(USDCOracle, badOracle, 1 days, 1 days)));
    }

    function testRevertsIfOracleIsStale() public {
        vm.warp(31337 + 2 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                IWatchtowerCustomErrors.PollTryAtEpoch.selector, block.timestamp + 1 days, "stale oracle"
            )
        );
        (uint256 priceNumerator, uint256 priceDenominator) =
            oracle.getPrice(USDC, WETH, abi.encode(getDefaultOracleData()));
    }

    function testRevertsIfOneOracleIsStale() public {
        // token0 is stale
        vm.warp(31337 + 2 days);
        vm.mockCall(
            USDCOracle,
            abi.encodeCall(AggregatorV3Interface.latestRoundData, ()),
            abi.encode(
                unusedRoundId,
                int256(1e8), // 1.00 with 8 decimals
                unusedStartedAt,
                2 days + 31336,
                unusedAnsweredInRound
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IWatchtowerCustomErrors.PollTryAtEpoch.selector, block.timestamp + 1 days, "stale oracle"
            )
        );
        oracle.getPrice(USDC, WETH, abi.encode(getDefaultOracleData()));
        // token1 is stale
        vm.mockCall(
            USDCOracle,
            abi.encodeCall(AggregatorV3Interface.latestRoundData, ()),
            abi.encode(
                unusedRoundId,
                int256(1e8), // 1.00 with 8 decimals
                unusedStartedAt,
                31336,
                unusedAnsweredInRound
            )
        );
        vm.mockCall(
            WETHOracle,
            abi.encodeCall(AggregatorV3Interface.latestRoundData, ()),
            abi.encode(
                unusedRoundId,
                int256(1e8), // 1.00 with 8 decimals
                unusedStartedAt,
                2 days + 31336,
                unusedAnsweredInRound
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IWatchtowerCustomErrors.PollTryAtEpoch.selector, block.timestamp + 1 days, "stale oracle"
            )
        );
        oracle.getPrice(USDC, WETH, abi.encode(getDefaultOracleData()));
    }
}
