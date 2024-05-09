// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {ValidateOrderParametersTest} from "./verify/ValidateOrderParametersTest.sol";
import {ValidateAmmMath} from "./verify/ValidateAmmMath.sol";

abstract contract VerifyTest is ValidateOrderParametersTest, ValidateAmmMath {}
