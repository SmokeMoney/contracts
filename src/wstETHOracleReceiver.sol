// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICrossDomainMessenger {
    function xDomainMessageSender() external view returns (address);
}

contract WstETHOracleReceiver {
    ICrossDomainMessenger public immutable L2_MESSENGER;
    address public L1_SENDER;

    uint256 public lastUpdatedRatio;
    uint256 public lastUpdatedBlockNumber;

    event ValueUpdated(uint256 value, uint256 blocknumber);

    constructor(ICrossDomainMessenger _l2Messenger, address _l1Sender) {
        L2_MESSENGER = _l2Messenger;
        L1_SENDER = _l1Sender;
    }

    modifier onlyL2Messenger() {
        require(msg.sender == address(L2_MESSENGER), "Only L2Messenger can call this function");
        _;
    }

    function setWstETHRatio(uint256 ratio) external onlyL2Messenger {
        
        // Verify that the message came from the Ethereum sender contract
        require(L2_MESSENGER.xDomainMessageSender() == L1_SENDER, "Invalid sender");

        lastUpdatedRatio = ratio;
        lastUpdatedBlockNumber = block.number;

        emit ValueUpdated(ratio, block.number);
    }

    function getLastUpdatedRatio() external view returns (uint256, uint256) {
        return (lastUpdatedRatio, lastUpdatedBlockNumber);
    }

    function setL1SenderContract(address _l1Sender) external {
        require(L1_SENDER == address(0), "Already set");
        L1_SENDER = _l1Sender;
    }
}