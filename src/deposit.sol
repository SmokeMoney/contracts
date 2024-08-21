// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
// import { console2 } from "forge-std/Test.sol"; // TODO REMOVE AFDTRER TEST

interface IBorrowContract {
    function getBorrowPositionSeparate(address issuerNFT, uint256 nftId, address wallet) external view returns (uint256, uint256, uint256);
    function getIssuerAddress(address issuerNFT) external view returns(address);
}

interface IWETH2 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

contract AdminDepositContract is ReentrancyGuard, OApp, OAppOptionsType3 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    struct IssuerData {
        bool isIssuerAnAsshole;
        mapping(address => bool) supportedTokens;
        mapping(address => mapping(uint256 => uint256)) deposits; // token => nftId => amount
        mapping(address => mapping(uint256 => bool)) liquidationLocks; // token => nftId => isLocked
        mapping(address => mapping(uint256 => uint256)) liquidationLockTimes; // token => nftId => lockTime
        mapping(address => mapping(uint256 => uint256)) issuerLocks; // token => nftId => lockedAmount
        mapping(uint256 => address) secondaryWithdrawalAddress; // nftId => Withdraw address
        mapping(uint256 => uint256) withdrawalNonces; // nftId => nonce
    }

    mapping(address => IssuerData) public issuers; // issuer NFT contract -> data
    address public immutable accOpsContractAddress;
    IBorrowContract public immutable borrowContract;
    address public immutable wethAddress;
    address public immutable wstETHAddress;
    uint32 public immutable nftContractChainId;
    uint32 public immutable chainId;
    IWETH2 public immutable WETH;

    uint256 public challengePeriod;

    uint256 public constant MIN_CHALLENGE_PERIOD = 24 hours;
    uint256 public constant LIQUIDATION_LOCK_PERCENTAGE = 1000; // 10%
    uint256 public constant SIGNATURE_VALIDITY = 5 minutes;

    event TokenAdded(address indexed token, address indexed issuerNFT);
    event TokenRemoved(address indexed token, address indexed issuerNFT);
    event Deposited(address indexed user, address indexed issuerNFT, uint256 indexed nftId, address token, uint256 amount);
    event WithdrawalExecuted(address indexed user, address indexed issuerNFT, uint256 indexed nftId, address token, uint256 amount);
    event CrossChainWithdrawalExecuted(address indexed user, address indexed issuerNFT, uint256 indexed nftId, address token, uint256 amount);
    event LiquidationLocked(address indexed token, address indexed issuerNFT, uint256 indexed nftId, uint256 amount, uint256 issuerLockAmount);
    event LiquidationExecuted(address indexed token, address indexed issuerNFT, uint256 indexed nftId, uint256 amount, uint256 issuerLockAmount);
    event LiquidationChallenged(address indexed token, address indexed issuerNFT, uint256 indexed nftId, address challenger);
    event PositionsReported(uint256 indexed assembleId, address indexed issuerNFT, uint256 indexed nftId);

    constructor(address _accOpsContract, address _borrowContract, address _wethAddress, address _wstETHAddress, uint32 _nftContractChainId, uint32 _chainId, address _endpoint, address _owner) OApp(_endpoint, _owner) Ownable(_owner){
        accOpsContractAddress = _accOpsContract;
        borrowContract = IBorrowContract(_borrowContract);
        wethAddress = _wethAddress;
        wstETHAddress = _wstETHAddress;
        nftContractChainId = _nftContractChainId;
        chainId = _chainId;
        WETH = IWETH2(_wethAddress);
        challengePeriod = MIN_CHALLENGE_PERIOD;
    }

    modifier onlyIssuer(address issuerNFT) {
        require(borrowContract.getIssuerAddress(issuerNFT) != address(0), "Invalid issuer");
        require(msg.sender == borrowContract.getIssuerAddress(issuerNFT), "Not the issuer");
        _;
    }

    function setChallengePeriod(uint256 newChallengePeriod) external onlyOwner {
        require(newChallengePeriod > MIN_CHALLENGE_PERIOD, "Challenge period too low");
        challengePeriod = newChallengePeriod;
    }

    function addSupportedToken(address token, address issuerNFT) external onlyIssuer(issuerNFT) {
        require(token != address(0), "Invalid token address");

        IssuerData storage issuerData = issuers[issuerNFT];
        issuerData.supportedTokens[token] = true;
        emit TokenAdded(token, issuerNFT);
    }

    function removeSupportedToken(address token, address issuerNFT) external onlyIssuer(issuerNFT) {
        IssuerData storage issuerData = issuers[issuerNFT];

        require(issuerData.supportedTokens[token], "Token not supported");
        issuerData.supportedTokens[token] = false;
        emit TokenRemoved(token, issuerNFT);
    }

    function deposit(address issuerNFT, address token, uint256 nftId, uint256 amount) external nonReentrant {
        IssuerData storage issuerData = issuers[issuerNFT];
        require(issuerData.supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(!issuerData.liquidationLocks[token][nftId], "Account is locked for liquidation");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        issuerData.deposits[token][nftId] += amount;

        emit Deposited(msg.sender, issuerNFT, nftId, token, amount);
    }

    function depositETH(address issuerNFT, uint256 nftId, uint256 amount) external payable nonReentrant {
        IssuerData storage issuerData = issuers[issuerNFT];
        require(amount > 0, "Amount must be greater than 0");
        require(amount == msg.value, "Amount must be equal to msg.value");
        require(!issuerData.liquidationLocks[wethAddress][nftId], "Account is locked for liquidation");

        WETH.deposit{value: amount}();
        issuerData.deposits[wethAddress][nftId] += amount;

        emit Deposited(msg.sender, issuerNFT, nftId, wethAddress, amount);
    }

    function secondaryWithdraw(
        address issuerNFT,
        bytes32 token,
        uint256 nftId,
        uint256 amount,
        uint32 targetChainId,
        uint256 timestamp,
        uint256 nonce,
        bool primary,
        bytes memory signature,
        bytes32 recipientAddress
    ) external payable {
        address issuerAddress = borrowContract.getIssuerAddress(issuerNFT);
        require( issuerAddress != address(0), "Invalid issuer");
        require( !primary, "Invalid withdrawal. Not a primary port");

        IssuerData storage issuerData = issuers[issuerNFT];
        require(issuerData.secondaryWithdrawalAddress[nftId] == msg.sender, 'Withdrawal not authorized');
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");

        require(nonce == issuerData.withdrawalNonces[nftId], "Invalid withdraw nonce");

        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, issuerNFT, token, nftId, amount, targetChainId, timestamp, nonce, primary));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuerAddress, "Invalid withdraw signature");

        executeWithdrawal(recipientAddress, token, issuerNFT, nftId, amount);
        issuerData.withdrawalNonces[nftId]++;
    }

    function executeWithdrawal(bytes32 recipientBytes32, bytes32 tokenBytes32, address issuerNFT, uint256 nftId, uint256 amount) public nonReentrant {
        address recipientAddress = bytes32ToAddress(recipientBytes32);
        address token = bytes32ToAddress(tokenBytes32);
        IssuerData storage issuerData = issuers[issuerNFT];
        require(msg.sender == address(accOpsContractAddress), "Only NFT contract can execute withdrawals");
        //@attackvector TODO can this lead to arbitrary function call from the NFT contract and malicious withdrawal?
        require(address(0) != address(accOpsContractAddress), "On-chain Withdrawals are not allowed on this chain");
        require(amount > 0, "Amount must be greater than 0");
        require(!issuerData.liquidationLocks[token][nftId], "Account is locked for liquidation");
        require(issuerData.deposits[token][nftId] >= amount, "Insufficient balance");

        issuerData.deposits[token][nftId] -= amount;
        if (token == wethAddress) {
            WETH.withdraw(amount);
            (bool success, ) = recipientAddress.call{value: amount}("");
            require(success, "ETH transfer failed");
        }
        else {
            IERC20(token).safeTransfer(recipientAddress, amount);
        }

        emit WithdrawalExecuted(recipientAddress, issuerNFT, nftId, token, amount);
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
                bytes32 recipientAddress,
                bytes32 token,
                bytes32 issuerNFT,
                uint256 nftId,
                uint256 amount
            ) = abi.decode(decodedPayload, (bytes32, bytes32, bytes32, uint256, uint256));
    
            _executeCrossChainWithdrawal(recipientAddress, token, issuerNFT, nftId, amount);
        }
        else if (msgType == 2) {
            (
                bytes32 recipientAddress,
                bytes32 token,
                bytes32 issuerNFT,
                uint256 nftId,
                uint256 timestamp,
                uint256 latestBorrowTimestamp
            ) = abi.decode(decodedPayload, (bytes32, bytes32, bytes32, uint256, uint256, uint256));

            _challengeLiquidation(token, issuerNFT, nftId, timestamp, latestBorrowTimestamp, recipientAddress);
        }
        else {
            (
                bytes32 issuerNFT,
                uint256 nftId,
                bytes32 secondaryWithdrawalAddress
            ) = abi.decode(decodedPayload, (bytes32, uint256, bytes32));
            issuers[bytes32ToAddress(issuerNFT)].secondaryWithdrawalAddress[nftId] = bytes32ToAddress(secondaryWithdrawalAddress);
        }
    }

    function decodeMessage(bytes calldata encodedMessage) public pure returns (uint8 msgType, bytes memory decodedPayload) {
        // @attackvector TODO wil this always work fine? 

        // Decode the first part of the message
        (msgType, decodedPayload) = abi.decode(encodedMessage, (uint8, bytes));
    }
    
    function _executeCrossChainWithdrawal(
        bytes32 recipientBytes32,
        bytes32 tokenBytes32,
        bytes32 issuerNFTBytes32,
        uint256 nftId,
        uint256 amount
    ) internal nonReentrant {
        address recipientAddress = bytes32ToAddress(recipientBytes32);
        address token = bytes32ToAddress(tokenBytes32);
        address issuerNFT = bytes32ToAddress(issuerNFTBytes32);

        IssuerData storage issuerData = issuers[issuerNFT];
        require(issuerData.supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(!issuerData.liquidationLocks[token][nftId], "Account is locked for liquidation");
        require(issuerData.deposits[token][nftId] >= amount, "Insufficient balance");

        issuerData.deposits[token][nftId] -= amount;
        if (token == wethAddress) {
            WETH.withdraw(amount);
            (bool success, ) = recipientAddress.call{value: amount}("");
            require(success, "ETH transfer failed");
        }
        else {
            IERC20(token).safeTransfer(recipientAddress, amount);
        }

        emit CrossChainWithdrawalExecuted(recipientAddress, issuerNFT, nftId, token, amount);
    }

    function reportPositions(uint256 assembleId, address issuerNFT, uint256 nftId, bytes32[] memory walletsBytes32, bytes calldata _extraOptions) external payable returns (bytes memory) {
        require(nftId != 0, 'Invalid NFT Id'); // @attackVector test this by removing it. I think the attack can mark a chain's borrow positions as 0. 
        IssuerData storage issuerData = issuers[issuerNFT];
        uint256[] memory borrowAmounts = new uint256[](walletsBytes32.length);
        uint256[] memory interestAmounts = new uint256[](walletsBytes32.length);
        uint256 latestBorrowTimestamp = 0;
        uint256 borrowTimestamp;
        for (uint256 i = 0; i < walletsBytes32.length; i++) {
            address wallet = bytes32ToAddress(walletsBytes32[i]);
            (borrowAmounts[i], interestAmounts[i], borrowTimestamp) = borrowContract.getBorrowPositionSeparate(issuerNFT, nftId, wallet);
            latestBorrowTimestamp = latestBorrowTimestamp > borrowTimestamp ? latestBorrowTimestamp : borrowTimestamp;
        }

        bytes memory payload = abi.encode(
            assembleId, 
            addressToBytes32(issuerNFT), 
            nftId, 
            issuerData.deposits[wethAddress][nftId],
            issuerData.deposits[wstETHAddress][nftId],
            addressToBytes32(wethAddress),
            addressToBytes32(wstETHAddress),
            latestBorrowTimestamp,
            walletsBytes32,
            borrowAmounts,
            interestAmounts
        );

        if (chainId == nftContractChainId) {
            emit PositionsReported(assembleId, issuerNFT, nftId);
            return payload;
        } else {
            _crossChainReport(payload, _extraOptions);
            emit PositionsReported(assembleId, issuerNFT, nftId);
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

    function lockForLiquidation(address issuerNFT, address token, uint256 nftId, uint256 amount) external onlyIssuer(issuerNFT) {
        IssuerData storage issuerData = issuers[issuerNFT];
        require(issuerData.supportedTokens[token], "Token not supported");
        require(issuerData.deposits[token][nftId] >= amount, "Insufficient balance for liquidation");
        require(!issuerData.liquidationLocks[token][nftId], "Account already locked for liquidation");

        uint256 issuerLockAmount = (amount * LIQUIDATION_LOCK_PERCENTAGE) / 10000;
        IERC20(token).safeTransferFrom(msg.sender, address(this), issuerLockAmount);

        issuerData.liquidationLocks[token][nftId] = true;
        issuerData.liquidationLockTimes[token][nftId] = block.timestamp;
        issuerData.issuerLocks[token][nftId] = issuerLockAmount;

        emit LiquidationLocked(token, issuerNFT, nftId, amount, issuerLockAmount);
    }

    function executeLiquidation(address issuerNFT, address token, uint256 nftId, uint256 amount) external onlyIssuer(issuerNFT) {
        IssuerData storage issuerData = issuers[issuerNFT];
        require(issuerData.liquidationLocks[token][nftId], "Account not locked for liquidation");
        require(block.timestamp >= issuerData.liquidationLockTimes[token][nftId] + challengePeriod, "Challenge period not over");

        uint256 issuerLockAmount = issuerData.issuerLocks[token][nftId];
        require(issuerData.deposits[token][nftId] >= amount, "Insufficient balance for liquidation");

        issuerData.liquidationLocks[token][nftId] = false;
        issuerData.deposits[token][nftId] -= amount;
        delete issuerData.issuerLocks[token][nftId];
        delete issuerData.liquidationLockTimes[token][nftId];

        address issuer = borrowContract.getIssuerAddress(issuerNFT);
        IERC20(token).safeTransfer(issuer, amount + issuerLockAmount);

        emit LiquidationExecuted(token, issuerNFT, nftId, amount, issuerLockAmount);
    }

    function onChainLiqChallenge(bytes32 token, bytes32 issuerNFT, uint256 nftId, uint256 assembleTimestamp, uint256 latestBorrowTimestamp, bytes32 recipient) external nonReentrant {
        require(msg.sender == address(accOpsContractAddress), "Only NFT contract can execute withdrawals");
        require(address(0) != address(accOpsContractAddress), "On-chain Withdrawals are not allowed on this chain");
        _challengeLiquidation(token, issuerNFT, nftId, assembleTimestamp, latestBorrowTimestamp, recipient);
    }

    function _challengeLiquidation(bytes32 tokenBytes32, bytes32 issuerNFTBytes32, uint256 nftId, uint256 assembleTimestamp, uint256 latestBorrowTimestamp, bytes32 recipientBytes32) internal {
        address token = bytes32ToAddress(tokenBytes32);
        address recipient = bytes32ToAddress(recipientBytes32);
        address issuerNFT = bytes32ToAddress(issuerNFTBytes32);        

        IssuerData storage issuerData = issuers[issuerNFT];

        require(issuerData.liquidationLocks[token][nftId], "Account not locked for liquidation");
        require(block.timestamp < issuerData.liquidationLockTimes[token][nftId] + challengePeriod, "Challenge period over");
        require(issuerData.liquidationLockTimes[token][nftId] < assembleTimestamp, "Assembled before liquidation lock");

        uint256 issuerLockAmount = issuerData.issuerLocks[token][nftId];
        issuerData.liquidationLocks[token][nftId] = false;
        delete issuerData.issuerLocks[token][nftId];
        delete issuerData.liquidationLockTimes[token][nftId];

        address issuer = borrowContract.getIssuerAddress(issuerNFT);
        if (issuerData.liquidationLockTimes[token][nftId] < latestBorrowTimestamp) {
            IERC20(token).safeTransfer(issuer, issuerLockAmount);
            emit LiquidationChallenged(token, issuerNFT, nftId, issuer);
        } else {
            issuerData.isIssuerAnAsshole = true;
            IERC20(token).safeTransfer(recipient, issuerLockAmount);
            emit LiquidationChallenged(token, issuerNFT, nftId, recipient);
        }
    }

    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function getDepositAmount(address issuerNFT, address token, uint256 nftId) external view returns (uint256) {
        return issuers[issuerNFT].deposits[token][nftId];
    }

    function isLiquidationLocked(address issuerNFT, address token, uint256 nftId) external view returns (bool) {
        return issuers[issuerNFT].liquidationLocks[token][nftId];
    }

    function getLiquidationLockTime(address issuerNFT, address token, uint256 nftId) external view returns (uint256) {
        return issuers[issuerNFT].liquidationLockTimes[token][nftId];
    }

    function getIssuerLockAmount(address issuerNFT, address token, uint256 nftId) external view returns (uint256) {
        return issuers[issuerNFT].issuerLocks[token][nftId];
    }

    function getCurrentNonce(address issuerNFT, uint256 nftId) external view returns (uint256) {
        return issuers[issuerNFT].withdrawalNonces[nftId];
    }

        /**
     * @dev Converts bytes32 to an address.
     * @param _b The bytes32 value to convert.
     * @return The address representation of bytes32.
     */
    function bytes32ToAddress(bytes32 _b) internal pure returns (address) {
        return address(uint160(uint256(_b)));
    }
        /**
     * @dev Converts an address to bytes32.
     * @param _addr The address to convert.
     * @return The bytes32 representation of the address.
     */
    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
