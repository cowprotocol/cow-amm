// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {VerifyTest} from "./ConstantProduct/VerifyTest.sol";
import {GetTradeableOrderTest} from "./ConstantProduct/GetTradeableOrderTest.sol";
import {CommitTest} from "./ConstantProduct/CommitTest.sol";
import {DeploymentParamsTest} from "./ConstantProduct/DeploymentParamsTest.sol";
import {IERC165Test} from "./ConstantProduct/IERC165Test.sol";

contract ConstantProductTest is VerifyTest, GetTradeableOrderTest, CommitTest, DeploymentParamsTest, IERC165Test {}
