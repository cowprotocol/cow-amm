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

    error SellTokenSameBuyToken();
    error PriceMovesTooMuch();
    error ZeroTokenAmount(address token, address who);

    uint256 internal constant PRICE_MOVEMENT_TOLERANCE_BPS = 10;
    uint256 internal constant BPS_COUNT = 10000;

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
        if (_sellToken == _buyToken) {
            revert SellTokenSameBuyToken();
        }
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
        uint128 deltaY = buyToken.balanceOf(address(stagingSafe)).toUint128();
        uint128 x = sellToken.balanceOf(fundingDst).toUint128();
        uint128 y = buyToken.balanceOf(fundingDst).toUint128();

        if (x == 0 || y == 0) {
            revert ZeroTokenAmount(address(x == 0 ? sellToken : buyToken), address(fundingDst));
        }

        uint256 deltaXFull;
        // TODO explain it's ok
        unchecked {
            deltaXFull = deltaY * x / y;
        }
        uint128 deltaX = deltaXFull.toUint128();

        // TODO Because of rounding issue explain explain
        if (movesAmmPriceTooMuch(x, deltaX, y, deltaY)) {
            revert PriceMovesTooMuch();
        }

        // Transfer bought tokens to fundingDst
        SafeModuleSafeERC20.safeTransfer(stagingSafe, buyToken, fundingDst, deltaY);

        // Transfer matching amount of `sellToken` to `fundingDst`. This would allow for
        // `sellToken` to be drained from the funding safe, however only if a "malicious"
        // user donated `buyToken` to the staging safe. We would also retain the
        // `buyToken` and `sellToken` in the AMM safe, so this is not a concern.
        SafeModuleSafeERC20.safeTransferFrom(stagingSafe, sellToken, fundingSrc, fundingDst, deltaX);
    }

    // TODO explain it comes from the following inequalities:
    //  x + Dx     y + Dy
    // -------- ≤ -------- · (1 + tolerance),
    //    x          y
    //  y + Dy     x + Dx
    // -------- ≤ -------- · (1 + tolerance),
    //    y          x
    // where tolerance = PRICE_MOVEMENT_TOLERANCE_BPS / BPS_COUNT
    function movesAmmPriceTooMuch(uint128 x, uint128 deltaX, uint128 y, uint128 deltaY) internal returns (bool) {
        // TODO explain why unchecked
        uint256 k;
        uint256 xDeltaY;
        uint256 yDeltaX;
        uint256 diff;
        unchecked {
            k = x * y;
            xDeltaY = x * deltaY;
            yDeltaX = y * deltaX;
        }

        if (xDeltaY < yDeltaX) {
            (xDeltaY, yDeltaX) = (yDeltaX, xDeltaY);
        }
        unchecked {
            diff = xDeltaY - yDeltaX;
        }
        uint256 kt = k * PRICE_MOVEMENT_TOLERANCE_BPS;
        uint256 rescaledDiff = diff * BPS_COUNT;
        uint256 yDeltaXT = yDeltaX * PRICE_MOVEMENT_TOLERANCE_BPS;
        return (rescaledDiff >= yDeltaXT) && (rescaledDiff - yDeltaXT > kt);
    }
}
