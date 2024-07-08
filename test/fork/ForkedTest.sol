// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

abstract contract ForkedTest is Test {
    string constant MAINNET_ARCHIVE_RPC = "https://eth.merkle.io";

    function forkMainnetAtBlock(uint256 blockNumber) internal returns (uint256) {
        return vm.createSelectFork(MAINNET_ARCHIVE_RPC, blockNumber);
    }
}
