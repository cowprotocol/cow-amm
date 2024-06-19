// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Deposit} from "./ConstantProductFactory/Deposit.sol";
import {Withdraw} from "./ConstantProductFactory/Withdraw.sol";
import {Create} from "./ConstantProductFactory/Create.sol";
import {DisableTrading} from "./ConstantProductFactory/DisableTrading.sol";

contract ConstantProductFactoryTest is Deposit, Withdraw, Create, DisableTrading {}
