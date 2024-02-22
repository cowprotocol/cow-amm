// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ValidateOrderParametersTest} from "./verify/ValidateOrderParametersTest.sol";
import {ValidateAmmMath} from "./verify/ValidateAmmMath.sol";
import {EnforceCommitmentTest} from "./verify/EnforceCommitmentTest.sol";

abstract contract VerifyTest is ValidateOrderParametersTest, ValidateAmmMath, EnforceCommitmentTest {}
