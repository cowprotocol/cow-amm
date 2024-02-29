// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {CreateAmmTest} from "./CowAmmModule/CreateAmm.sol";
import {ReplaceAmmTest} from "./CowAmmModule/ReplaceAmm.sol";
import {CloseAmmTest} from "./CowAmmModule/CloseAmm.sol";
import {DeploymentParamsTest} from "./CowAmmModule/DeploymentParamsTest.sol";

contract CowAmmModuleTest is CreateAmmTest, ReplaceAmmTest, CloseAmmTest, DeploymentParamsTest {}
