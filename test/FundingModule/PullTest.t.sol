// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0 <0.9.0;

import {FundingModuleTestHarness, IERC20} from "./FundingModuleTestHarness.sol";

contract PullTest is FundingModuleTestHarness {
    function setUp() public virtual override(FundingModuleTestHarness) {
        super.setUp();
        setUpTokenAmounts();
    }

    function testSimplePull() public {
        // pull tokens from the funding src to the staging safe
        fundingModule.pull();

        // check that the staging safe has the correct amount of tokens
        assertEq(token0.balanceOf(address(stagingSafe)), 10000e18);
    }

    function testPullTwiceAssertSingleTransfer() public {
        // pull tokens from the funding src to the staging safe
        fundingModule.pull();
        fundingModule.pull();

        // check that the staging safe has the correct amount of tokens
        assertEq(token0.balanceOf(address(stagingSafe)), 10000e18);
    }

    function testPullWithResidualBalance() public {
        // deal some tokens to the staging safe to create a residual
        deal(address(token0), address(safe1), 1000e18);

        // pull tokens from the funding src to the staging safe
        fundingModule.pull();

        // check that the staging safe has the correct amount of tokens
        assertEq(token0.balanceOf(address(stagingSafe)), 10000e18);
    }
}
