// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDepositContract {
    function executeWithdrawal(
        bytes32 user,
        bytes32 token,
        address issuerNFT,
        uint256 nftId,
        uint256 amount
    ) external;

    function reportPositions(
        uint256 assembleId,
        address issuerNFT,
        uint256 nftId,
        bytes32[] memory wallets,
        bytes calldata _extraOptions
    ) external payable returns (bytes memory);

    function onChainLiqChallenge(
        bytes32 issuerNFT,
        uint256 nftId,
        bytes32 token,
        uint256 assembleTimestamp,
        uint256 latestBorrowTimestamp,
        bytes32 recipient
    ) external;
}
