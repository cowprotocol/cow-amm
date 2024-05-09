// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {CreateAMM} from "./Create/CreateAMM.sol";
import {DeterministicDeployment} from "./Create/DeterministicDeployment.sol";

abstract contract Create is CreateAMM, DeterministicDeployment {}
