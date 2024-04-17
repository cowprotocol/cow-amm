// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {VerifyTest} from "./ConstantProduct/VerifyTest.sol";
import {GetTradeableOrderTest} from "./ConstantProduct/GetTradeableOrderTest.sol";
import {CommitTest} from "./ConstantProduct/CommitTest.sol";
import {DeploymentParamsTest} from "./ConstantProduct/DeploymentParamsTest.sol";
import {EnableTrading} from "./ConstantProduct/EnableTrading.sol";
import {DisableTrading} from "./ConstantProduct/DisableTrading.sol";
import {IsValidSignature} from "./ConstantProduct/IsValidSignature.sol";

contract ConstantProductTest is
    VerifyTest,
    GetTradeableOrderTest,
    CommitTest,
    DeploymentParamsTest,
    EnableTrading,
    DisableTrading,
    IsValidSignature
{}
