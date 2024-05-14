// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

abstract contract CowProtocolSetUp is Test {
    function setUpSettlementContract() internal {
        address settlementContract = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
        vm.etch(settlementContract, hex"1337");
        vm.mockCall(
            settlementContract, abi.encodeWithSignature("domainSeparator()"), abi.encode(bytes32("domain separator"))
        );
        vm.mockCall(
            settlementContract, abi.encodeWithSignature("vaultRelayer()"), abi.encode(makeAddr("vault relayer"))
        );
        // Reverts for everything else
        vm.mockCallRevert(settlementContract, hex"", abi.encode("Called unexpected function on settlement contract"));
    }

    function setUpComposableCowContract() internal {
        vm.etch(0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74, hex"1337");
    }
}
