// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./interfaces/ISmokeSpendingContract.sol";

contract SpendingConfig is Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    struct InterestRateChange {
        uint256 timestamp;
        uint256 rate;
    }

    struct IssuerDataConfig {
        // uint256 borrowInterestRate;
        uint256 scheduleInterestRate;
        uint256 scheduleInterestRateTimestamp;
        mapping(uint256 => InterestRateChange[]) interestRateHistory;
        // uint256 borrowFees;
        uint256 scheduleBorrowFees;
        uint256 scheduleBorrowFeesTimestamp;
    }

    // uint256 autogasThreshold;
    // uint256 autogasRefillAmount;
    // uint256 gasPriceThreshold;

    uint256 interestRateChangeDelay;
    uint256 maxAutogasThreshold;
    uint256 maxAutogasRefillAmount;
    uint256 minGasPriceThreshold;

    ISmokeSpendingContract spendingContract;
    mapping(address => IssuerDataConfig) public issuers; // issuer NFT Address -> issuerDataConf

    event InterestRateChangeScheduled(
        address indexed issuerNFT, uint256 oldRate, uint256 newRate, uint256 effectiveTimestamp
    );

    constructor(address _owner, address _spendingContract) Ownable(_owner) {
        spendingContract = ISmokeSpendingContract(_spendingContract);
    }

    modifier onlyIssuer(address issuerNFT) {
        address issuerAddress = spendingContract.getIssuerAddress(issuerNFT);
        require(issuerAddress != address(0), "Invalid issuer");
        require(msg.sender == issuerAddress, "Not the issuer");
        _;
    }

    function scheduleInterestRateChange(address issuerNFT, uint256 newRate) external onlyIssuer(issuerNFT) {
        IssuerDataConfig storage issuerDataConf = issuers[issuerNFT];
        uint256 oldRate = spendingContract.getBorrowInterestRate(issuerNFT);
        require(newRate <= oldRate * 150 / 100, "can't be increased by more than 50%");

        issuerDataConf.scheduleInterestRate = newRate;
        issuerDataConf.scheduleInterestRateTimestamp = block.timestamp;
        emit InterestRateChangeScheduled(issuerNFT, oldRate, newRate, block.timestamp + interestRateChangeDelay);
    }

    function setInterestRate(address issuerNFT) external onlyIssuer(issuerNFT) {
        IssuerDataConfig storage issuerDataConf = issuers[issuerNFT];
        require(issuerDataConf.scheduleInterestRate != 0, "No scheduled rate change");
        require(
            block.timestamp > issuerDataConf.scheduleInterestRateTimestamp + interestRateChangeDelay,
            "Delay period not yet passed"
        );
        uint256 newRate = issuerDataConf.scheduleInterestRate;
        spendingContract.getBorrowInterestRate(issuerNFT);
        spendingContract.setInterestRate(issuerNFT, newRate);
        issuerDataConf.interestRateHistory[newRate].push(InterestRateChange(block.timestamp, newRate));
        issuerDataConf.scheduleInterestRate = 0;
        issuerDataConf.scheduleInterestRateTimestamp = 0;
    }

    function setMaxRepayGas(uint256 _newRepayGas) external onlyOwner {
        spendingContract.setMaxRepayGas(_newRepayGas);
    }
}
