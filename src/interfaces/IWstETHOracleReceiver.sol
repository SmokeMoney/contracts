// SPDX-License-Identifier: CTOSL
pragma solidity ^0.8.0;

interface IWstETHOracleReceiver {
    function getLastUpdatedRatio() external view returns (uint256, uint256);
}
