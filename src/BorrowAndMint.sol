// SPDX-License-Identifier: CTOSL
pragma solidity ^0.8.0;

import "./interfaces/ISmokeSpendingContract.sol";

interface IZora {
    function mint(address mintTo, uint256 quantity, address collection, uint256 tokenId, address mintReferral, string calldata comment) external payable;
}

contract SpendingConfig {
    ISmokeSpendingContract spendingContract;

    constructor(address _spendingContract) {
        spendingContract = ISmokeSpendingContract(_spendingContract);
    }

    function borrowAndMint() external {

    }
}