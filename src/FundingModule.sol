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

    address private constant HOOKS_TRAMPOLINE = 0x01DcB88678aedD0C4cC9552B20F4718550250574;

    IERC20 public immutable sellToken;
    IERC20 public immutable buyToken;
    ISafe public immutable stagingSafe;
    address public immutable fundingSrc;
    address public immutable fundingDst;

    uint256 public immutable sellAmount;

    modifier onlyTrampoline() {
        require(msg.sender == HOOKS_TRAMPOLINE, "FundingModule: caller is not the trampoline");
        _;
    }

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
     * @dev Requires calling from the trampoline to ensure the call is part of a settlement
     * @dev No guarding against multiple calls from multiple batches, as worst case, all allowed
     *      funds are pulled from the `fundingSrc` to the staging safe (where they would remain).
     */
    function pull() external onlyTrampoline {
        SafeModuleSafeERC20.safeTransferFrom(
            stagingSafe, // safe that has this module enabled
            sellToken, // token being transferred from
            fundingSrc, // address to transfer from
            address(stagingSafe), // address to transfer to
            sellAmount // amount to transfer
        );
    }

    /**
     * @notice Push bought tokens, and a corresponding amount of `sellToken`s to `fundingDst`.
     * @dev Requires calling from the trampoline to ensure the call is part of a settlement
     * @dev If this hook fails to be included in a settlement due to a malicious solver, the
     *      next discrete order will be able to include the requisite amounts.
     */
    function push() external onlyTrampoline {
        uint256 boughtAmount = buyToken.balanceOf(address(stagingSafe));

        uint112 x = buyToken.balanceOf(fundingDst).toUint112();
        uint112 y = sellToken.balanceOf(fundingDst).toUint112();

        // x * y has a maximum value of 2^224, which is less than 2^256-1, so this is safe
        // If x + boughtAmount is greater than 2^224 (`boughtAmount` may be 2^256 - 1), the
        // denominator will be greater than the numerator resulting in
        // `requiredSelltokenReserves` = 0. This has implications for underflow protection
        // on `topUpSellTokenAmount`, which is why `topUpSellTokenAmount` is checked but
        // `requiredSellTokenReserves` is not.
        uint256 requiredSellTokenReserves;
        unchecked {
            requiredSellTokenReserves = x * y / (x + boughtAmount);
        }

        uint256 topUpSellTokenAmount = requiredSellTokenReserves - y;

        // Transfer bought tokens to fundingDst
        SafeModuleSafeERC20.safeTransferFrom(stagingSafe, buyToken, address(stagingSafe), fundingDst, boughtAmount);

        // Transfer matching amount of sellToken to fundingDst
        SafeModuleSafeERC20.safeTransferFrom(
            stagingSafe, sellToken, address(fundingSrc), fundingDst, topUpSellTokenAmount
        );
    }
}
