// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0 <0.9.0;

import {IERC20} from "lib/composable-cow/lib/@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeCast} from "lib/composable-cow/lib/@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ISafe} from "./vendored/interfaces/ISafe.sol";
import {SafeModuleSafeERC20} from "./vendored/libraries/SafeModuleSafeERC20.sol";

/**
 * @title CoW AMM Funding Module
 * @author CoW Protocol Developers
 * @dev A privileged module that allows using Hooks in combination with TWAP to fund CoW AMMs.
 *      **NOTE**: Any hook that fails to execute will *NOT* cause the entire settlement to fail.
 */
contract FundingModule {
    using SafeCast for uint256;

    uint112 SCALING_FACTOR = 1e9;

    IERC20 public immutable sellToken;
    IERC20 public immutable buyToken;
    ISafe public immutable stagingSafe;
    address public immutable fundingSrc;
    address public immutable fundingDst;

    uint256 public immutable sellAmount;

    constructor(
        IERC20 _sellToken,
        IERC20 _buyToken,
        ISafe _stagingSafe,
        address _fundingSrc,
        address _fundingDst,
        uint256 _sellAmount
    ) {
        require(_sellToken != _buyToken, "FundingModule: sellToken and buyToken must be different");
        sellToken = _sellToken;
        buyToken = _buyToken;
        stagingSafe = _stagingSafe;
        fundingSrc = _fundingSrc;
        fundingDst = _fundingDst;
        sellAmount = _sellAmount;
    }

    /**
     * @notice Pulls the `sellToken` from the `fundingSrc` to the staging safe.
     * @dev Will not pull more than `sellAmount` tokens per discrete order.
     */
    function pull() external {
        uint256 stagingSellTokenBalance = sellToken.balanceOf(address(stagingSafe));

        // Do not pull any tokens if there is already enough in the staging safe
        if (stagingSellTokenBalance >= sellAmount) {
            return;
        }

        SafeModuleSafeERC20.safeTransferFrom(
            stagingSafe, // safe that has this module enabled
            sellToken, // token being transferred from
            fundingSrc, // address to transfer from
            address(stagingSafe), // address to transfer to
            sellAmount - stagingSellTokenBalance // amount to transfer
        );
    }

    /**
     * @notice Push bought tokens, and a corresponding amount of `sellToken`s to `fundingDst`.
     * @dev If this hook fails to be included in a settlement due to a malicious solver, the
     * next discrete order will be able to include the requisite amounts.
     */
    function push() external {
        uint112 boughtAmount = buyToken.balanceOf(address(stagingSafe)).toUint112();
        uint112 x = buyToken.balanceOf(fundingDst).toUint112();
        uint112 y = sellToken.balanceOf(fundingDst).toUint112();

        // `y` * `boughtAmount * SCALING_FACTOR` has a maximum value of ~2^254, which is less
        // than 2^256-1 so this is safe for overflow.
        uint256 topUpSellTokenAmount;
        unchecked {
            topUpSellTokenAmount = y * boughtAmount * SCALING_FACTOR / x / SCALING_FACTOR;
        }

        // Transfer bought tokens to fundingDst
        SafeModuleSafeERC20.safeTransfer(stagingSafe, buyToken, fundingDst, deltaY);

        // Transfer matching amount of `sellToken` to `fundingDst`. This would allow for
        // `sellToken` to be drained from the funding safe, however only if a "malicious"
        // user donated `buyToken` to the staging safe. We would also retain the
        // `buyToken` and `sellToken` in the AMM safe, so this is not a concern.
        SafeModuleSafeERC20.safeTransferFrom(
            stagingSafe, sellToken, address(fundingSrc), fundingDst, topUpSellTokenAmount
        );
    }
}
