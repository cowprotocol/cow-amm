// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {VerifyTest} from "./ConstantProduct/VerifyTest.sol";
import {GetTradeableOrderTest} from "./ConstantProduct/GetTradeableOrderTest.sol";
import {Ierc165Test} from "./ConstantProduct/Ierc165Test.sol";

contract ConstantProductTest is VerifyTest, GetTradeableOrderTest, Ierc165Test {}
