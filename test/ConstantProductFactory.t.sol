// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GetTradeableOrderWithSignature} from "./ConstantProductFactory/GetTradeableOrderWithSignature.sol";
import {Deposit} from "./ConstantProductFactory/Deposit.sol";
import {Withdraw} from "./ConstantProductFactory/Withdraw.sol";

contract ConstantProductFactoryTest is GetTradeableOrderWithSignature, Deposit, Withdraw {}
