// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {BalancerSetUp} from "./single-deployment/balancer/BalancerSetUp.sol";
import {CowProtocolSetUp} from "./single-deployment/cow-protocol/CowProtocolSetUp.sol";
import {SafeSetUp} from "./single-deployment/safe/SafeSetUp.sol";

import {DeployAllContracts} from "script/DeployAllContracts.s.sol";

contract DeployAllContractsTest is Test, BalancerSetUp, CowProtocolSetUp, SafeSetUp {
    DeployAllContracts script;

    function setUp() public {
        setUpSettlementContract();
        setUpComposableCowContract();
        setUpBalancerVault();
        setUpSafeExtensibleFallbackHandler();

        vm.setEnv("TOKEN_0", "0x1111111111111111111111111111111111111111");
        vm.setEnv("TOKEN_1", "0x2222222222222222222222222222222222222222");

        script = new DeployAllContracts();
    }

    function testDoesNotRevert() public {
        script.run();
    }
}
