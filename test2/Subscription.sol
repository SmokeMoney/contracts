// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ISmokeSpendingContract.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract SubscriptionManager is Ownable, EIP712 {
    using ECDSA for bytes32;

    ISmokeSpendingContract public spendingContract;
    
    struct Subscription {
        address subscriber;
        uint256 nftId;
        uint256 amount;
        uint256 frequency; // in seconds (e.g., 86400 for daily, 2592000 for monthly)
        uint256 lastBorrowTime;
        uint256 startTime;
        uint256 duration; // Duration of the subscription in seconds
        bool status;
    }

    mapping(uint256 => mapping(uint256 => Subscription)) public subscriptions;
    mapping(uint256 => uint256) public subscriptionsCounter;

    event SubscriptionCreated(address indexed user, address indexed subscriber, uint256 amount, uint256 frequency, uint256 duration);
    event BorrowExecuted(address indexed user, uint256 amount, uint256 timestamp);

    constructor(address _spendingContract) EIP712("SubscriptionManager", "1") Ownable(msg.sender) {
        spendingContract = ISmokeSpendingContract(_spendingContract);
    }

    function subscribe(
        address issuerNFT,
        uint256 nftId,
        uint256 amount,
        uint256 frequency,
        uint256 duration,
        bytes memory signature
    ) external {
        address signer = _validateSubscription(
            msg.sender, issuerNFT, nftId, amount, frequency, duration, signature
        );
        
        require(signer == msg.sender, "Invalid subscription signature");
        

        subscriptions[nftId][subscriptionsCounter[nftId]++] = Subscription({
            subscriber: msg.sender,
            nftId: nftId,
            amount: amount,
            frequency: frequency,
            lastBorrowTime: block.timestamp,
            startTime: block.timestamp,
            duration: duration,
            status: true
        });

        emit SubscriptionCreated(msg.sender, msg.sender, amount, frequency, duration);
    }

    function executeBorrow(
        address issuerNFT,
        address user,
        uint256 nftId,
        bytes memory signature
    ) external {
        Subscription storage subscription = subscriptions[nftId];
        require(subscription.subscriber == msg.sender, "Not authorized to borrow");
        require(subscription.amount > 0, "Invalid subscription");
        require(block.timestamp >= subscription.lastBorrowTime + subscription.frequency, "Too soon to borrow again");
        require(block.timestamp <= subscription.startTime + subscription.duration, "Subscription expired");

        // Call the borrow function on SmokeSpendingContract
        spendingContract.borrow(
            issuerNFT,
            nftId,
            subscription.amount,
            block.timestamp,
            signature,
            spendingContract.getCurrentNonce(issuerNFT, nftId),
            subscription.subscriber, // Send to the subscriber
            false, // Assume not WETH for simplicity
            "" // Use an empty signature for simplicity (could be extended)
        );

        subscription.lastBorrowTime = block.timestamp;

        emit BorrowExecuted(user, subscription.amount, block.timestamp);
    }

    function _validateSubscription(
        address user,
        address issuerNFT,
        uint256 nftId,
        uint256 amount,
        uint256 frequency,
        uint256 duration,
        bytes memory signature
    ) internal view returns (address) {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            SUBSCRIBE_TYPEHASH,
            user,
            issuerNFT,
            nftId,
            amount,
            frequency,
            duration
        )));
        return ECDSA.recover(digest, signature);
    }
}
