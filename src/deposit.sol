// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";


interface ICrossChainLendingAccount {
    function ownerOf(uint256 tokenId) external view returns (address);
    function isWalletApproved(uint256 tokenId, address wallet) external view returns (bool);
}

contract AdminDepositContract is ReentrancyGuard, OApp, OAppOptionsType3 {
using SafeERC20 for IERC20;
using ECDSA for bytes32;

address public immutable issuer;
ICrossChainLendingAccount public immutable nftContract;
mapping(address => bool) public supportedTokens;
mapping(address => mapping(uint256 => uint256)) public deposits; // token => nftId => amount
mapping(address => mapping(uint256 => bool)) public liquidationLocks; // token => nftId => isLocked
mapping(address => mapping(uint256 => uint256)) public liquidationLockTimes; // token => nftId => lockTime
mapping(address => mapping(uint256 => uint256)) public issuerLocks; // token => nftId => lockedAmount
mapping(uint256 => uint256) public withdrawalNonces; // nftId => nonce

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

constructor(address _issuer, address _nftContract, address _endpoint, address _owner) OApp(_endpoint, _owner) Ownable(_owner){
    issuer = _issuer;
    nftContract = ICrossChainLendingAccount(_nftContract);
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

function executeWithdrawal(address user, address token, uint256 nftId, uint256 amount) external nonReentrant {
    require(msg.sender == address(nftContract), "Only NFT contract can execute withdrawals");
    require(address(0) != address(nftContract), "On-chain Withdrawal are not allowed on this chain");
    require(supportedTokens[token], "Token not supported");
    require(amount > 0, "Amount must be greater than 0");
    require(!liquidationLocks[token][nftId], "Account is locked for liquidation");
    require(deposits[token][nftId] >= amount, "Insufficient balance");

    deposits[token][nftId] -= amount;
    IERC20(token).safeTransfer(user, amount);

    emit WithdrawalExecuted(user, token, nftId, amount);
}

function _lzReceive(
    Origin calldata _origin, // struct containing info about the message sender
    bytes32 _guid, // global packet identifier
    bytes calldata payload, // encoded message payload being received
    address _executor, // the Executor address.
    bytes calldata _extraData // arbitrary data appended by the Executor
    ) internal override {
    
    (   
        address user,
        address token,
        uint256 nftId,
        uint256 amount,
        uint256 withdrawalNonce
    ) = abi.decode(payload, (address, address, uint256, uint256, uint256));

    _executeCrossChainWithdrawal(user, token, nftId, amount, withdrawalNonce);
}


function _executeCrossChainWithdrawal(
    address user,
    address token,
    uint256 nftId,
    uint256 amount,
    uint256 nonce
) internal nonReentrant {

    require(supportedTokens[token], "Token not supported");
    require(amount > 0, "Amount must be greater than 0");
    require(!liquidationLocks[token][nftId], "Account is locked for liquidation");
    require(deposits[token][nftId] >= amount, "Insufficient balance");
    require(nonce != withdrawalNonces[nftId], "Invalid cross nonce");

    deposits[token][nftId] -= amount;
    IERC20(token).safeTransfer(user, amount);
    withdrawalNonces[nftId] = nonce;

    emit CrossChainWithdrawalExecuted(user, token, nftId, amount);
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

function challengeLiquidation(address token, uint256 nftId, bytes calldata proof) external nonReentrant {
    require(liquidationLocks[token][nftId], "Account not locked for liquidation");
    require(block.timestamp < liquidationLockTimes[token][nftId] + CHALLENGE_PERIOD, "Challenge period over");

    require(verifyChallenge(token, nftId, proof), "Invalid challenge proof");

    uint256 issuerLockAmount = issuerLocks[token][nftId];
    liquidationLocks[token][nftId] = false;
    delete issuerLocks[token][nftId];
    delete liquidationLockTimes[token][nftId];

    IERC20(token).safeTransfer(msg.sender, issuerLockAmount);

    emit LiquidationChallenged(token, nftId, msg.sender);
}

function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
}

function verifyChallenge(address token, uint256 nftId, bytes calldata proof) internal pure returns (bool) {
    // TODO: Implement challenge verification
    // This function should verify the proof provided by the challenger
    // to ensure that the liquidation was indeed invalid
    return false; // Placeholder return
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
