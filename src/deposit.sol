// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { console2 } from "forge-std/Test.sol"; // TODO REMOVE AFDTRER TEST

interface IBorrowContract {
    function getBorrowPositionSeparate(uint256 nftId, address wallet) external view returns (uint256, uint256, uint256);
}

interface IWETH2 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

contract AdminDepositContract is ReentrancyGuard, OApp, OAppOptionsType3 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    address public issuer;
    address public immutable accOpsContractAddress;
    address public immutable wethAddress;
    address public immutable wstETHAddress;
    uint32 public immutable nftContractChainId;
    uint32 public immutable chainId;
    IWETH2 public immutable WETH;

    IBorrowContract public immutable borrowContract;
    mapping(address => bool) public supportedTokens;
    mapping(address => mapping(uint256 => uint256)) public deposits; // token => nftId => amount
    mapping(address => mapping(uint256 => bool)) public liquidationLocks; // token => nftId => isLocked
    mapping(address => mapping(uint256 => uint256)) public liquidationLockTimes; // token => nftId => lockTime
    mapping(address => mapping(uint256 => uint256)) public issuerLocks; // token => nftId => lockedAmount
    mapping(uint256 => uint256) public withdrawalNonces; // nftId => nonce
    mapping(uint256 => uint256) public challengeNonces; // nftId => nonce

    uint256 public constant CHALLENGE_PERIOD = 24 hours;
    uint256 public constant LIQUIDATION_LOCK_PERCENTAGE = 10; // 10%
    uint256 public constant SIGNATURE_VALIDITY = 5 minutes;
    string public data = "Nothing received yet";
    uint16 public constant SEND = 1;
    uint16 public constant SEND_ABA = 2;

    event TokenAdded(address token);
    event TokenRemoved(address token);
    event Deposited(address indexed user, address indexed token, uint256 indexed nftId, uint256 amount);
    event WithdrawalExecuted(address indexed user, address indexed token, uint256 indexed nftId, uint256 amount);
    event CrossChainWithdrawalExecuted(address indexed user, address indexed token, uint256 indexed nftId, uint256 amount);
    event LiquidationLocked(address indexed token, uint256 indexed nftId, uint256 amount, uint256 issuerLockAmount);
    event LiquidationExecuted(address indexed token, uint256 indexed nftId, uint256 amount, uint256 issuerLockAmount);
    event LiquidationChallenged(address indexed token, uint256 indexed nftId, address challenger);
    event PositionsReported(uint256 indexed assembleId, uint256 indexed nftId);


    constructor(address _accOpsContract, address _borrowContract, address _wethAddress, address _wstETHAddress, uint32 _nftContractChainId, uint32 _chainId, address _endpoint, address _issuer, address _owner) OApp(_endpoint, _owner) Ownable(_owner){
        issuer = _issuer;
        accOpsContractAddress = _accOpsContract;
        borrowContract = IBorrowContract(_borrowContract);
        wethAddress = _wethAddress;
        wstETHAddress = _wstETHAddress;
        nftContractChainId = _nftContractChainId;
        chainId = _chainId;
        WETH = IWETH2(_wethAddress);
    }

    modifier onlyIssuer() {
        require(msg.sender == issuer, "Not the issuer");
        _;
    }

    function addSupportedToken(address token) external onlyIssuer {
        require(token != address(0), "Invalid token address");
        require(!supportedTokens[token], "Token already supported");
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    function removeSupportedToken(address token) external onlyIssuer {
        require(supportedTokens[token], "Token not supported");
        supportedTokens[token] = false;
        emit TokenRemoved(token);
    }

    function deposit(address token, uint256 nftId, uint256 amount) external nonReentrant {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(!liquidationLocks[token][nftId], "Account is locked for liquidation");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        deposits[token][nftId] += amount;

        emit Deposited(msg.sender, token, nftId, amount);
    }

    function depositETH(uint256 nftId, uint256 amount) external payable nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(amount == msg.value, "Amount must be equal to msg.value");
        require(!liquidationLocks[wethAddress][nftId], "Account is locked for liquidation");

        WETH.deposit{value: amount}();
        deposits[wethAddress][nftId] += amount;

        emit Deposited(msg.sender, wethAddress, nftId, amount);
    }

    function executeWithdrawal(address recipientAddress, address token, uint256 nftId, uint256 amount) external nonReentrant {
        require(msg.sender == address(accOpsContractAddress), "Only NFT contract can execute withdrawals"); 
        //@attackvector TODO can this lead to arbitrary function call from the NFT contract and malicious withdrawal?
        require(address(0) != address(accOpsContractAddress), "On-chain Withdrawals are not allowed on this chain");
        require(amount > 0, "Amount must be greater than 0");
        require(!liquidationLocks[token][nftId], "Account is locked for liquidation");
        require(deposits[token][nftId] >= amount, "Insufficient balance");

        deposits[token][nftId] -= amount;   
        IERC20(token).safeTransfer(recipientAddress, amount);

        emit WithdrawalExecuted(recipientAddress, token, nftId, amount);
    }

    function _lzReceive(
        Origin calldata _origin, // struct containing info about the message sender
        bytes32 _guid, // global packet identifier
        bytes calldata payload, // encoded message payload being received
        address _executor, // the Executor address.
        bytes calldata _extraData // arbitrary data appended by the Executor
        ) internal override 
    {
        
        (uint8 msgType, bytes memory decodedPayload) = decodeMessage(payload);
        if (msgType == 1){
            (
                address recipientAddress,
                address token,
                uint256 nftId,
                uint256 amount,
                uint256 withdrawalNonce
            ) = abi.decode(decodedPayload, (address, address, uint256, uint256, uint256));
    
            _executeCrossChainWithdrawal(recipientAddress, token, nftId, amount, withdrawalNonce);
        }
        else {
            (
                address recipientAddress,
                address token,
                uint256 nftId,
                uint256 timestamp,
                uint256 latestBorrowTimestamp,
                uint256 challengeNonce
            ) = abi.decode(decodedPayload, (address, address, uint256, uint256, uint256, uint256));

            _crossChainLiqChallenge(token, nftId, timestamp, latestBorrowTimestamp, recipientAddress, challengeNonce);
        }
    }

    function decodeMessage(bytes calldata encodedMessage) public pure returns (uint8 msgType, bytes memory decodedPayload) {
        // @attackvector TODO wil this always work fine? 

        // Decode the first part of the message
        (msgType, decodedPayload) = abi.decode(encodedMessage, (uint8, bytes));
    }
    

    function _executeCrossChainWithdrawal(
        address recipientAddress,
        address token,
        uint256 nftId,
        uint256 amount,
        uint256 nonce
    ) internal nonReentrant {

        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(!liquidationLocks[token][nftId], "Account is locked for liquidation");
        require(deposits[token][nftId] >= amount, "Insufficient balance");
        require(nonce != withdrawalNonces[nftId], "Invalid cross nonce"); // @attackvector TODO I'm making sure a cross chain message can't be reused. Is this already handled by LZ? 

        deposits[token][nftId] -= amount;
        IERC20(token).safeTransfer(recipientAddress, amount);
        withdrawalNonces[nftId] = nonce;

        emit CrossChainWithdrawalExecuted(recipientAddress, token, nftId, amount);
    }

    function reportPositions(uint256 assembleId, uint256 nftId, address[] memory wallets, bytes calldata _extraOptions) external payable returns (bytes memory) {
        uint256[] memory borrowAmounts = new uint256[](wallets.length);
        uint256[] memory interestAmounts = new uint256[](wallets.length);
        uint256 latestBorrowTimestamp = 0;
        uint256 borrowTimestamp;
        for (uint256 i = 0; i < wallets.length; i++) {
            (borrowAmounts[i], interestAmounts[i], borrowTimestamp) = borrowContract.getBorrowPositionSeparate(nftId, wallets[i]);
            latestBorrowTimestamp = latestBorrowTimestamp > borrowTimestamp ? latestBorrowTimestamp : borrowTimestamp;
        }


        bytes memory payload = abi.encode(
            assembleId, 
            nftId, 
            deposits[wethAddress][nftId], //depositAmount
            deposits[wstETHAddress][nftId], //wstETHDepositAmount
            wethAddress, 
            wstETHAddress, 
            latestBorrowTimestamp, 
            wallets, 
            borrowAmounts,
            interestAmounts
        );

        if (chainId == nftContractChainId) {
            emit PositionsReported(assembleId, nftId);
            return payload;
        }
        else {
            _crossChainReport(payload, _extraOptions);
            emit PositionsReported(assembleId, nftId);
            return payload;
        }
    }

    function _crossChainReport(bytes memory payload, bytes calldata _extraOptions) internal {
        _lzSend(
            nftContractChainId,
            payload,
            _extraOptions,
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
    }

    function quote(
        uint32 targetChainId,
        uint16 _msgType,
        bytes calldata _payload,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {

        fee = _quote(targetChainId, _payload, _extraOptions, _payInLzToken);
    }

    function lockForLiquidation(address token, uint256 nftId, uint256 amount) external onlyIssuer {
        require(supportedTokens[token], "Token not supported");
        require(deposits[token][nftId] >= amount, "Insufficient balance for liquidation");
        require(!liquidationLocks[token][nftId], "Account already locked for liquidation");

        uint256 issuerLockAmount = (amount * LIQUIDATION_LOCK_PERCENTAGE) / 100;
        IERC20(token).safeTransferFrom(msg.sender, address(this), issuerLockAmount);

        liquidationLocks[token][nftId] = true;
        liquidationLockTimes[token][nftId] = block.timestamp;
        issuerLocks[token][nftId] = issuerLockAmount;

        emit LiquidationLocked(token, nftId, amount, issuerLockAmount);
    }

    function executeLiquidation(address token, uint256 nftId, uint256 amount) external onlyIssuer {
        require(liquidationLocks[token][nftId], "Account not locked for liquidation");
        require(block.timestamp >= liquidationLockTimes[token][nftId] + CHALLENGE_PERIOD, "Challenge period not over");

        uint256 issuerLockAmount = issuerLocks[token][nftId];
        require(deposits[token][nftId] >= amount, "Insufficient balance for liquidation");

        liquidationLocks[token][nftId] = false;
        deposits[token][nftId] -= amount;
        delete issuerLocks[token][nftId];
        delete liquidationLockTimes[token][nftId];

        IERC20(token).safeTransfer(issuer, amount + issuerLockAmount);

        emit LiquidationExecuted(token, nftId, amount, issuerLockAmount);
    }

    function onChainLiqChallenge(address token, uint256 nftId, uint256 assembleTimestamp, uint256 latestBorrowTimestamp, address recipient) external nonReentrant {
        require(msg.sender == address(accOpsContractAddress), "Only NFT contract can execute withdrawals");
        require(address(0) != address(accOpsContractAddress), "On-chain Withdrawals are not allowed on this chain");
        _challengeLiquidation(token, nftId, assembleTimestamp, latestBorrowTimestamp, recipient);
    }

    function _crossChainLiqChallenge(address token, uint256 nftId, uint256 assembleTimestamp, uint256 latestBorrowTimestamp, address recipient, uint256 nonce) internal nonReentrant {
        require(nonce != challengeNonces[nftId], "Invalid cross chain challenge nonce"); // @attackvector TODO I'm making sure a cross chain message can't be reused. Is this already handled by LZ? 
        _challengeLiquidation(token, nftId, assembleTimestamp, latestBorrowTimestamp, recipient);
        challengeNonces[nftId] = nonce;
    }

    function _challengeLiquidation(address token, uint256 nftId, uint256 assembleTimestamp, uint256 latestBorrowTimestamp, address recipient) internal {
        require(liquidationLocks[token][nftId], "Account not locked for liquidation");
        require(block.timestamp < liquidationLockTimes[token][nftId] + CHALLENGE_PERIOD, "Challenge period over");
        require(liquidationLockTimes[token][nftId] < assembleTimestamp, "Assembled before liquidation lock");

        uint256 issuerLockAmount = issuerLocks[token][nftId];
        liquidationLocks[token][nftId] = false;
        delete issuerLocks[token][nftId];
        delete liquidationLockTimes[token][nftId];
        if (liquidationLockTimes[token][nftId] < latestBorrowTimestamp) {
            IERC20(token).safeTransfer(issuer, issuerLockAmount);
            emit LiquidationChallenged(token, nftId, issuer);
        }
        else {
            IERC20(token).safeTransfer(recipient, issuerLockAmount);
            emit LiquidationChallenged(token, nftId, recipient);
        }
    }

    function setNewIssuer(address newIssuer) external onlyIssuer {
        issuer = newIssuer;
    }

    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function getDepositAmount(address token, uint256 nftId) external view returns (uint256) {
        return deposits[token][nftId];
    }

    function isLiquidationLocked(address token, uint256 nftId) external view returns (bool) {
        return liquidationLocks[token][nftId];
    }

    function getLiquidationLockTime(address token, uint256 nftId) external view returns (uint256) {
        return liquidationLockTimes[token][nftId];
    }

    function getIssuerLockAmount(address token, uint256 nftId) external view returns (uint256) {
        return issuerLocks[token][nftId];
    }

    function getCurrentNonce(uint256 nftId) external view returns (uint256) {
        return withdrawalNonces[nftId];
    }
}
