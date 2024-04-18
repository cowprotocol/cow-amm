// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ValidateOrderHash} from "./isValidSignature/ValidateOrderHash.sol";
import {EnforceCommitmentTest} from "./isValidSignature/EnforceCommitmentTest.sol";

abstract contract IsValidSignature is ValidateOrderHash, EnforceCommitmentTest {}
