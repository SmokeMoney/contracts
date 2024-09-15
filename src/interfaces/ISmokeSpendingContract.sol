// SPDX-License-Identifier: CTOSL
pragma solidity ^0.8.0;

interface ISmokeSpendingContract {
    function getBorrowPositionSeparate(
        address issuerNFT,
        uint256 nftId,
        address wallet
    ) external view returns (uint256, uint256, uint256);

    function getIssuerAddress(
        address issuerNFT
    ) external view returns (address);

    function borrow(
        address issuerNFT,
        uint256 nftId,
        uint256 amount,
        uint256 timestamp,
        uint256 signatureValidity,
        uint256 nonce,
        bool weth,
        bytes memory signature
    ) external;

    function getBorrowInterestRate(
        address issuerNFT
    ) external view returns (uint256);

    function setInterestRate(address issuerNFT, uint256 newRate) external;
    function setMaxRepayGas(uint256 _newRepayGas) external;
}
