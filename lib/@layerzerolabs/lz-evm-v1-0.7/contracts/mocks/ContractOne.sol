// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;

contract ContractOne {
    uint x;

    function setIt(uint _x) external {
        x = _x;
    }
}
