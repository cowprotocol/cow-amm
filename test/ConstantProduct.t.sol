// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {VerifyTest} from "./ConstantProduct/VerifyTest.sol";
import {GetTradeableOrderTest} from "./ConstantProduct/GetTradeableOrderTest.sol";
import {CommitTest} from "./ConstantProduct/CommitTest.sol";

contract ConstantProductTest is VerifyTest, GetTradeableOrderTest, CommitTest {}
