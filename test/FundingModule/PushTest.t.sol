// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0 <0.9.0;

import {FundingModuleTestHarness, IERC20} from "./FundingModuleTestHarness.sol";

contract PushTest is FundingModuleTestHarness {
    function setUp() public virtual override(FundingModuleTestHarness) {
        super.setUp();
        setUpTokenAmounts();
        setUpAmmReserves();
    }

    function testPushNoStagingBoughtTokens() public {
        // push tokens from the staging safe to the funding dst
        fundingModule.push();

        // check that the staging safe has the correct amount of tokens
        assertEq(token0.balanceOf(address(stagingSafe)), 0);
        assertEq(token1.balanceOf(address(stagingSafe)), 0);
        assertEq(token0.balanceOf(address(fundingDst)), AMM_TOKEN0_AMOUNT);
        assertEq(token1.balanceOf(address(fundingDst)), AMM_TOKEN1_AMOUNT);
    }

    function testMultiPushNoStagingBoughtTokens() public {
        // push tokens from the staging safe to the funding dst
        fundingModule.push();
        fundingModule.push();

        // check that the staging safe has the correct amount of tokens
        assertEq(token0.balanceOf(address(stagingSafe)), 0);
        assertEq(token1.balanceOf(address(stagingSafe)), 0);
        assertEq(token0.balanceOf(address(fundingDst)), AMM_TOKEN0_AMOUNT);
        assertEq(token1.balanceOf(address(fundingDst)), AMM_TOKEN1_AMOUNT);
    }

    function testPushWithStagingBoughtTokens() public {
        setUpBoughtTokens();
        // cache destination funding safe balances
        (uint256 x, uint256 y) = _fetchTokenBalances(address(fundingDst));

        // cache source funding safe balances
        (uint256 srcToken0Balance, uint256 srcToken1Balance) = _fetchTokenBalances(address(fundingSrc));

        // cache staging safe balances
        (uint256 stagingToken0Balance, uint256 stagingToken1Balance) = _fetchTokenBalances(address(stagingSafe));

        // push tokens from the staging safe to the funding dst
        fundingModule.push();

        // Should have perfectly flushed the staging safe
        assertEq(token0.balanceOf(address(stagingSafe)), 0);
        assertEq(token1.balanceOf(address(stagingSafe)), 0);

        uint256 deltaY = BOUGHT_AMOUNT;

        // Should have transferred the correct amount of tokens to the dst
        uint256 deltaX = deltaY * x / y;
        assertEq(token0.balanceOf(address(fundingDst)), x + deltaX);
        assertEq(token1.balanceOf(address(fundingDst)), y + deltaY);

        // Do assertions for source safe
        assertEq(token0.balanceOf(address(fundingSrc)), srcToken0Balance - deltaX);
        assertEq(token1.balanceOf(address(fundingSrc)), 0);
    }

    function _fetchTokenBalances(address who) internal view returns (uint256, uint256) {
        return (token0.balanceOf(who), token1.balanceOf(who));
    }
}
