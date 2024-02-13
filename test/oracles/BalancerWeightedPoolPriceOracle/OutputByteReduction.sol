// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";

import {Utils} from "test/libraries/Utils.sol";
import {BalancerWeightedPoolPriceOracle, IVault} from "src/oracles/BalancerWeightedPoolPriceOracle.sol";

contract OutputByteReductionTest is Test {
    WrapperBalancerWeightedPoolPriceOracle internal oracle;
    uint256 internal tolerance;

    function setUp() public {
        oracle = new WrapperBalancerWeightedPoolPriceOracle();
        tolerance = oracle.tolerance();
    }

    function testReducesAmount() public {
        (uint256 out1, uint256 out2) = oracle.reducer(1 << (128 + 42), 1 << (128 - 24));
        assertEq(out1, 1 << 128);
        assertEq(out2, 1 << (128 - 24 - 42));
    }

    function testReducesAmountWhenSecondLarger() public {
        (uint256 out1, uint256 out2) = oracle.reducer(1 << (128 - 24), 1 << (128 + 42));
        assertEq(out1, 1 << (128 - 24 - 42));
        assertEq(out2, 1 << 128);
    }

    function testReducesAmountExplicitBytes() public {
        // 128 bytes = 16 bytes.
        //                kept (16 bytes)                 cut off
        // Ruler:       |------------------------------||xxxxxxxxxxxxxxxxxxxxxxxxxxx|
        uint256 in1 = 0xf123456789012345678901234567890123456789012345678901234567890;
        uint256 ou1 = 0xf1234567890123456789012345678901;
        // From ruler above:                  |xxxxxxxxxxxxxxxxxxxxxxxxxxx|
        uint256 in2 = 0xf98765432109876543210987654321098765432109876543210;
        uint256 ou2 = 0xf987654321098765432109;
        (uint256 out1, uint256 out2) = oracle.reducer(in1, in2);
        assertEq(out1, ou1);
        assertEq(out2, ou2);
    }

    function testReducesAmountRoundingMaxUp() public {
        (uint256 out1, uint256 out2) = oracle.reducer((1 << (128 + 42)) + 1, 1 << (128 - 24));
        assertEq(out1, (1 << (128 - 1)));
        assertEq(out2, 1 << (128 - 24 - 42 - 1));
    }

    function testReturnsInputIfAmountsAreSmall() public {
        uint256 in1 = 1 << 128;
        uint256 in2 = in1 - 1;
        (uint256 out1, uint256 out2) = oracle.reducer(in1, in2);
        assertEq(out1, in1);
        assertEq(out2, in2);
        // One unit more and the test would fail
        in1 = in1 + 1;
        (out1, out2) = oracle.reducer(in1, in2);
        assertFalse(out1 == in1);
        assertFalse(out2 == in2);
    }

    function testReturnsInputIfMinBelowTolerance() public {
        uint256 in1 = (1 << (tolerance + 1)) - 1;
        uint256 in2 = type(uint256).max;
        (uint256 out1, uint256 out2) = oracle.reducer(in1, in2);
        assertEq(out1, in1);
        assertEq(out2, in2);
        // One unit more and the test would fail
        in1 = in1 + 1;
        (out1, out2) = oracle.reducer(in1, in2);
        assertFalse(out1 == in1);
        assertFalse(out2 == in2);
    }

    function testCapsReductionIfMinAmountWouldGoBelowTolerance() public {
        (uint256 out1, uint256 out2) = oracle.reducer(1 << (tolerance + 42), 1 << 255);
        assertEq(out1, 1 << tolerance);
        assertEq(out2, 1 << (255 - 42));
    }

    function testToleranceIsLessThanOneBasePoint() public {
        assertTrue((1 << tolerance) > 10000);
    }
}

// Wrapper that makes the function `reduceOutputBytes` public
contract WrapperBalancerWeightedPoolPriceOracle is BalancerWeightedPoolPriceOracle {
    uint256 public tolerance = TOLERANCE;

    // The Balancer address is irrelevant
    constructor() BalancerWeightedPoolPriceOracle(IVault(address(0))) {}

    function reducer(uint256 num1, uint256 num2) public pure returns (uint256, uint256) {
        return reduceOutputBytes(num1, num2);
    }
}
