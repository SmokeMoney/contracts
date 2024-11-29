// SPDX-License-Identifier: CTOSL
pragma solidity ^0.8.0;

interface IAssemblePositionsContract {
    function setupAssemble(uint32 srcChainId, bytes memory _payload) external returns (uint256);
    function verifyAllChainsReported(uint256 assembleId) external view;
    function calculateTotatPositionsWithdrawal(uint256 assembleId, uint256 nftId)
        external
        view
        returns (uint256 totalBorrowed, uint256 totalCollateral);
    function verifyLiquidationThreshold(uint256 assembleId, uint256[] memory gAssembleIds) external view;
    function calculateTimestamps(uint256 assembleId, uint256[] memory gAssembleIds)
        external
        view
        returns (uint256 lowestAssembleTimestamp, uint256 latestBorrowTimestamp);
    function getAssembleWstETHAddresses(uint256 assembleId, uint256 chainId) external view returns (bytes32);
    function getAssemblePositionsBasic(uint256 assembleId)
        external
        view
        returns (
            address issuerNFT,
            uint256 nftId,
            bool isComplete,
            bool forWithdrawal,
            uint256 timestamp,
            uint256 wstETHRatio,
            address executor,
            uint256 totalAvailableToWithdraw,
            uint256 latestBorrowTimestamp
        );
    function markAssembleComplete(uint256 assembleId) external;
    function setTotalAvailableToWithdraw(uint256 assembleId, uint256 _totalAvailableToWithdraw) external;
}
