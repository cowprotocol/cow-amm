// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0 <0.9.0;

import {Base} from "lib/composable-cow/test/Base.t.sol";
import {FundingModule, IERC20, ISafe} from "../../src/FundingModule.sol";

abstract contract FundingModuleTestHarness is Base {
    // --- constants
    uint256 constant FUNDING_AMOUNT = 1_000_000e18;
    uint256 constant AMM_TOKEN0_AMOUNT = 50_000e18;
    uint256 constant AMM_TOKEN1_AMOUNT = 100_000e18;
    uint256 constant SELL_AMOUNT = 10_000e18;
    uint256 constant BOUGHT_AMOUNT = 20_000e18;

    // --- variables
    FundingModule fundingModule;
    ISafe stagingSafe;
    address fundingSrc;
    address fundingDst;

    function setUp() public virtual override(Base) {
        super.setUp();

        stagingSafe = ISafe(address(safe1));
        fundingSrc = address(safe2);
        fundingDst = address(safe3);

        // create a funding module
        fundingModule = new FundingModule(
            IERC20(address(token0)), IERC20(address(token1)), stagingSafe, fundingSrc, fundingDst, SELL_AMOUNT
        );

        // enable the funding module on the staging safe
        vm.prank(address(stagingSafe));
        safe1.enableModule(address(fundingModule));

        // set the allowance for the staging safe on the funding src
        vm.prank(address(fundingSrc));
        token0.approve(address(stagingSafe), FUNDING_AMOUNT);
    }

    function setUpTokenAmounts() internal {
        // give some tokens to the funding src
        deal(address(token0), address(fundingSrc), FUNDING_AMOUNT);

        vm.startPrank(address(stagingSafe));
        token0.transfer(address(1), token0.balanceOf(address(stagingSafe)));
        vm.stopPrank();
    }

    function setUpAmmReserves() internal {
        // set the reserves of the AMM (deal it some tokens)
        deal(address(token0), address(fundingDst), AMM_TOKEN0_AMOUNT);
        deal(address(token1), address(fundingDst), AMM_TOKEN1_AMOUNT);
    }

    function setUpBoughtTokens() internal {
        // deal some tokens to the staging safe to create a residual
        deal(address(token1), address(stagingSafe), BOUGHT_AMOUNT);
    }
}
