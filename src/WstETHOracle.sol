// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICrossDomainMessenger {
    function sendMessage(
        address _target,
        bytes calldata _message,
        uint32 _gasLimit
    ) external;
}

interface WstETHOracleReceiver {
    function setWstETHRatio(
        uint256 ratio
    ) external;
}

interface WstETH {
    function stEthPerToken() external view returns (uint256);
}

contract WstETHOracle {
    ICrossDomainMessenger public immutable L1_MESSENGER;
    WstETHOracleReceiver public immutable L2_RECEIVER;
    WstETH public immutable WSTETH_CONTRACT;

    constructor(
        ICrossDomainMessenger _messenger,
        WstETHOracleReceiver _l2Receiver,
        WstETH _wstETHContract
    ) {
        L1_MESSENGER = _messenger;
        L2_RECEIVER = _l2Receiver;
        WSTETH_CONTRACT = _wstETHContract;
    }

    function updateWstETHRatio() public {
        uint256 ratio = WSTETH_CONTRACT.stEthPerToken();
        L1_MESSENGER.sendMessage(
            address(L2_RECEIVER),
            abi.encodeCall(
                WstETHOracleReceiver.setWstETHRatio,
                (ratio)
            ),
            200000
        );
    }
}