// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {VerifyTest} from "./ConstantProduct/VerifyTest.sol";
import {CommitTest} from "./ConstantProduct/CommitTest.sol";
import {DeploymentParamsTest} from "./ConstantProduct/DeploymentParamsTest.sol";
import {EnableTrading} from "./ConstantProduct/EnableTrading.sol";
import {DisableTrading} from "./ConstantProduct/DisableTrading.sol";
import {IsValidSignature} from "./ConstantProduct/IsValidSignature.sol";

contract ConstantProductTest is
    VerifyTest,
    CommitTest,
    DeploymentParamsTest,
    EnableTrading,
    DisableTrading,
    IsValidSignature
{}
