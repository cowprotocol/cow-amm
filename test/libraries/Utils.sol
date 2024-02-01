// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

library Utils {
    function addressFromString(string memory s) internal pure returns (address) {
        return address(uint160(uint256(keccak256(bytes(s)))));
    }
}
