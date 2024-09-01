// SPDX-License-Identifier: CTOSL
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { console2 } from "forge-std/Test.sol"; // TODO REMOVE AFDTRER TEST

import "./interfaces/ISmokeSpendingContract.sol";

interface IWETH2 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function balanceOf(address a) external view returns (uint256);
    function transfer(address dst, uint wad) external returns (bool);
}

contract SmokeDepositContract is EIP712, ReentrancyGuard, OApp, OAppOptionsType3 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    struct IssuerData {
        bool isIssuerAnAsshole;
        mapping(address => bool) supportedTokens;
        mapping(address => mapping(uint256 => uint256)) deposits; // token => nftId => amount
        mapping(address => mapping(uint256 => bool)) liquidationLocks; // token => nftId => isLocked
        mapping(address => mapping(uint256 => uint256)) liquidationLockTimes; // token => nftId => lockTime
        mapping(address => mapping(uint256 => uint256)) issuerLocks; // token => nftId => lockedAmount
        mapping(address => mapping(uint256 => uint256)) challengerLocks; // token => nftId => lockedAmount
        mapping(address => mapping(uint256 => address)) challengers; // token => nftId => challenger address
        mapping(uint256 => address) secondaryWithdrawalAddress; // nftId => Withdraw address
        mapping(uint256 => uint256) withdrawalNonces; // nftId => nonce
    }

    struct SecondaryWithdrawParams {
        address issuerNFT;
        bytes32 token;
        uint256 nftId;
        uint256 amount;
        uint32 targetChainId;
        uint256 timestamp;
        uint256 nonce;
        bool primary;
        bytes32 recipientAddress;
    }

    bytes32 private constant SECONDARY_WITHDRAW_TYPEHASH = keccak256(
        "SecondaryWithdraw(address issuerNFT,bytes32 token,uint256 nftId,uint256 amount,uint32 targetChainId,uint256 timestamp,uint256 nonce,bool primary,bytes32 recipientAddress)"
    );

    mapping(address => IssuerData) public issuers; // issuer NFT contract -> data
    address public immutable accOpsContractAddress;
    ISmokeSpendingContract public immutable spendingContract;
    address public immutable wethAddress;
    address public immutable wstETHAddress;
    uint32 public immutable adminChainId;
    uint32 public immutable chainId;
    IWETH2 public immutable WETH;

    uint256 public constant MIN_CHALLENGE_PERIOD = 24 hours;
    uint256 public constant EXTENDED_CHALLENGE_PERIOD = 16 days;
    uint256 public constant LIQUIDATION_LOCK_PERCENTAGE = 1000; // 10%
    uint256 public constant CHALLENGER_LOCK_PERCENTAGE = 1000; // 10%
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
    event QuickChallengeInitiated(address indexed token, address indexed issuerNFT, uint256 indexed nftId, address challenger, uint256 lockedAmount);

    constructor(address _accOpsContract, address _spendingContract, address _wethAddress, address _wstETHAddress, uint32 _adminChainId, uint32 _chainId, address _endpoint, address _owner) 
        OApp(_endpoint, _owner) 
        Ownable(_owner)
        EIP712("SmokeDepositContract", "1")
    {
        accOpsContractAddress = _accOpsContract;
        spendingContract = ISmokeSpendingContract(_spendingContract);
        wethAddress = _wethAddress;
        wstETHAddress = _wstETHAddress;
        adminChainId = _adminChainId;
        chainId = _chainId;
        WETH = IWETH2(_wethAddress);
    }

    modifier onlyIssuer(address issuerNFT) {
        require(spendingContract.getIssuerAddress(issuerNFT) != address(0), "Invalid issuer");
        require(msg.sender == spendingContract.getIssuerAddress(issuerNFT), "Not the issuer");
        _;
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
        SecondaryWithdrawParams memory params,
        bytes memory signature
    ) external payable {
        address issuerAddress = spendingContract.getIssuerAddress(params.issuerNFT);
        require(issuerAddress != address(0), "Invalid issuer");
        require(!params.primary, "Invalid withdrawal. Not a primary port");

        IssuerData storage issuerData = issuers[params.issuerNFT];
        require(issuerData.secondaryWithdrawalAddress[params.nftId] == msg.sender, 'Withdrawal not authorized');
        require(block.timestamp <= params.timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(params.nonce == issuerData.withdrawalNonces[params.nftId], "Invalid withdraw nonce");

        _validateWithdrawSignature(params, signature, issuerAddress);

        executeWithdrawal(params.recipientAddress, params.token, params.issuerNFT, params.nftId, params.amount);
        issuerData.withdrawalNonces[params.nftId]++;
    }

    function _validateWithdrawSignature(
        SecondaryWithdrawParams memory params,
        bytes memory signature,
        address issuerAddress
    ) internal view {
        bytes32 structHash = keccak256(abi.encode(
            SECONDARY_WITHDRAW_TYPEHASH,
            params.issuerNFT,
            params.token,
            params.nftId,
            params.amount,
            params.targetChainId,
            params.timestamp,
            params.nonce,
            params.primary,
            params.recipientAddress
        ));

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, signature);
        require(signer == issuerAddress, "Invalid withdraw signature");
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

        if (token == wethAddress) {            

            // Check if the contract has enough WETH balance
            require(WETH.balanceOf(address(this)) >= amount, "Insufficient WETH balance");
            WETH.transfer(recipientAddress, amount);

            // IERC20(token).safeTransfer(recipientAddress, amount);
            // try WETH.withdraw(amount) {
            //     (bool success, ) = recipientAddress.call{value: amount}("");
            //     require(success, "ETH transfer failed");
            // } catch Error(string memory reason) {
            //     console2.log("Withdrawal failed with reason: %s", reason);
            // } catch (bytes memory lowLevelData) {
            //     console2.log("Withdrawal failed with low-level error");
            //     console2.logBytes(lowLevelData);
            // } Someone help please. 

        }
        else {
            IERC20(token).safeTransfer(recipientAddress, amount);
        }
        issuerData.deposits[token][nftId] -= amount;

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

            _challengeLiquidation(issuerNFT, nftId, token, timestamp, latestBorrowTimestamp, recipientAddress);
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

        if (token == wethAddress) {
            // WETH.withdraw(amount);
            // (bool success, ) = recipientAddress.call{value: amount}("");
            // require(success, "ETH transfer failed"); HELP HELP HELP

            require(WETH.balanceOf(address(this)) >= amount, "Insufficient WETH balance");
            WETH.transfer(recipientAddress, amount);
            // console2.log("This contract: %s | IssuerNFT: %s | NFTId: %s", address(this), issuerNFT, nftId); // TODO remove after testing
            // console2.log("This contract: %s | IssuerNFT: %s | Balance: %s", address(this), issuerNFT, issuers[issuerNFT].deposits[token][nftId]); // TODO remove after testing
        }
        else {
            IERC20(token).safeTransfer(recipientAddress, amount);
        }
        issuerData.deposits[token][nftId] -= amount;

        emit CrossChainWithdrawalExecuted(recipientAddress, issuerNFT, nftId, token, amount);
    }

    function reportPositions(uint256 assembleId, address issuerNFT, uint256 nftId, bytes32[] memory walletsBytes32, bytes calldata _extraOptions) external payable returns (bytes memory) {
        require(nftId != 0, 'Invalid NFT Id'); // @attackVector test this by removing it. I think the attack can mark a chain's borrow positions as 0. 

        bytes memory payload = _gatherReportDataAndEncode(assembleId, issuerNFT, nftId, walletsBytes32);

        if (chainId == adminChainId) {
            emit PositionsReported(assembleId, issuerNFT, nftId);
            return payload;
        } else {
            _crossChainReport(payload, _extraOptions);
            emit PositionsReported(assembleId, issuerNFT, nftId);
            return payload;
        }
    }

    function _gatherReportDataAndEncode(uint256 assembleId, address issuerNFT, uint256 nftId, bytes32[] memory walletsBytes32) internal view returns (bytes memory) {
        IssuerData storage issuerData = issuers[issuerNFT];
        
        uint256[] memory borrowAmounts = new uint256[](walletsBytes32.length);
        uint256[] memory interestAmounts = new uint256[](walletsBytes32.length);
        uint256 latestBorrowTimestamp = 0;

        for (uint256 i = 0; i < walletsBytes32.length; i++) {
            address wallet = bytes32ToAddress(walletsBytes32[i]);
            uint256 borrowTimestamp;
            (borrowAmounts[i], interestAmounts[i], borrowTimestamp) = spendingContract.getBorrowPositionSeparate(issuerNFT, nftId, wallet);
            latestBorrowTimestamp = latestBorrowTimestamp > borrowTimestamp ? latestBorrowTimestamp : borrowTimestamp;
        }

        console2.logBytes32(addressToBytes32(issuerNFT));
        return abi.encode(
            assembleId,
            addressToBytes32(issuerNFT),
            nftId,
            issuerData.deposits[wethAddress][nftId],
            issuerData.deposits[wstETHAddress][nftId],
            addressToBytes32(wstETHAddress),
            latestBorrowTimestamp,
            block.timestamp,
            walletsBytes32,
            borrowAmounts,
            interestAmounts
        );
    }

    function _crossChainReport(bytes memory payload, bytes calldata _extraOptions) internal {
        _lzSend(
            adminChainId,
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

    function lockForLiquidation(address issuerNFT, uint256 nftId, address token) external onlyIssuer(issuerNFT) {
        IssuerData storage issuerData = issuers[issuerNFT];
        require(issuerData.supportedTokens[token], "Token not supported");
        require(!issuerData.liquidationLocks[token][nftId], "Account already locked for liquidation");

        uint256 issuerLockAmount = (issuerData.deposits[token][nftId] * LIQUIDATION_LOCK_PERCENTAGE) / 10000;
        IERC20(token).safeTransferFrom(msg.sender, address(this), issuerLockAmount);

        issuerData.liquidationLocks[token][nftId] = true;
        issuerData.liquidationLockTimes[token][nftId] = block.timestamp;
        issuerData.issuerLocks[token][nftId] = issuerLockAmount;

        emit LiquidationLocked(token, issuerNFT, nftId, issuerData.deposits[token][nftId], issuerLockAmount);
    }

    function quickChallenge(address issuerNFT, uint256 nftId, address token) external nonReentrant {
        IssuerData storage issuerData = issuers[issuerNFT];
        require(issuerData.liquidationLocks[token][nftId], "Account not locked for liquidation");
        require(block.timestamp < issuerData.liquidationLockTimes[token][nftId] + MIN_CHALLENGE_PERIOD, "Initial challenge period over");
        require(issuerData.challengerLocks[token][nftId] == 0, "Already challenged");

        uint256 challengerLockAmount = (issuerData.deposits[token][nftId] * CHALLENGER_LOCK_PERCENTAGE) / 10000;

        IERC20(token).safeTransferFrom(msg.sender, address(this), challengerLockAmount);

        issuerData.challengerLocks[token][nftId] = challengerLockAmount;
        issuerData.challengers[token][nftId] = msg.sender;

        emit QuickChallengeInitiated(token, issuerNFT, nftId, msg.sender, challengerLockAmount);
    }

    function executeLiquidation(address issuerNFT, uint256 nftId, address token) external onlyIssuer(issuerNFT) {
        IssuerData storage issuerData = issuers[issuerNFT];
        require(issuerData.liquidationLocks[token][nftId], "Account not locked for liquidation");
        
        uint256 challengePeriod = issuerData.challengerLocks[token][nftId] > 0 ? EXTENDED_CHALLENGE_PERIOD : MIN_CHALLENGE_PERIOD;
        require(block.timestamp >= issuerData.liquidationLockTimes[token][nftId] + challengePeriod, "Challenge period not over");
        
        address issuer = spendingContract.getIssuerAddress(issuerNFT);
        IERC20(token).safeTransfer(issuer, issuerData.deposits[token][nftId] + issuerData.issuerLocks[token][nftId]);

        // Return challenger's deposit if there was a quick challenge
        if (issuerData.challengerLocks[token][nftId] > 0) {
            IERC20(token).safeTransfer(issuer, issuerData.challengerLocks[token][nftId]);
        }

        issuerData.liquidationLocks[token][nftId] = false;
        issuerData.deposits[token][nftId] = 0;

        delete issuerData.issuerLocks[token][nftId];
        delete issuerData.liquidationLockTimes[token][nftId];
        delete issuerData.challengerLocks[token][nftId];
        delete issuerData.challengers[token][nftId];

        emit LiquidationExecuted(token, issuerNFT, nftId, issuerData.deposits[token][nftId], issuerData.issuerLocks[token][nftId]);
    }

    function onChainLiqChallenge(bytes32 issuerNFT, uint256 nftId, bytes32 token, uint256 assembleTimestamp, uint256 latestBorrowTimestamp, bytes32 recipient) external nonReentrant {
        require(msg.sender == address(accOpsContractAddress), "Only NFT contract can execute withdrawals");
        require(address(0) != address(accOpsContractAddress), "On-chain Withdrawals are not allowed on this chain");
        _challengeLiquidation(issuerNFT, nftId, token, assembleTimestamp, latestBorrowTimestamp, recipient);
    }
    
    function _challengeLiquidation(bytes32 issuerNFTBytes32, uint256 nftId, bytes32 tokenBytes32, uint256 assembleTimestamp, uint256 latestBorrowTimestamp, bytes32 recipientBytes32) internal {
        address token = bytes32ToAddress(tokenBytes32);
        address recipient = bytes32ToAddress(recipientBytes32);
        address issuerNFT = bytes32ToAddress(issuerNFTBytes32);

        IssuerData storage issuerData = issuers[issuerNFT];

        require(issuerData.liquidationLocks[token][nftId], "Account not locked for liquidation");
        
        uint256 challengePeriod = issuerData.challengerLocks[token][nftId] > 0 ? EXTENDED_CHALLENGE_PERIOD : MIN_CHALLENGE_PERIOD;
        require(block.timestamp < issuerData.liquidationLockTimes[token][nftId] + challengePeriod, "Challenge period over");
        require(issuerData.liquidationLockTimes[token][nftId] < assembleTimestamp, "Assembled before liquidation lock");
        
        address issuer = spendingContract.getIssuerAddress(issuerNFT);

        if (issuerData.liquidationLockTimes[token][nftId] < latestBorrowTimestamp) {
            IERC20(token).safeTransfer(issuer, issuerData.issuerLocks[token][nftId]);
            if (issuerData.challengerLocks[token][nftId] > 0) {
                IERC20(token).safeTransfer(issuerData.challengers[token][nftId], (issuerData.challengerLocks[token][nftId] * 9000) / 10000 );
                IERC20(token).safeTransfer(issuer, (issuerData.challengerLocks[token][nftId] * 1000) / 10000);
            }
            emit LiquidationChallenged(token, issuerNFT, nftId, issuer);
        } else {
            issuerData.isIssuerAnAsshole = true;
            IERC20(token).safeTransfer(issuerData.challengers[token][nftId], issuerData.challengerLocks[token][nftId] + (issuerData.issuerLocks[token][nftId] * 2500) / 10000 );
            IERC20(token).safeTransfer(recipient, (issuerData.issuerLocks[token][nftId] * 7500) / 10000);
            emit LiquidationChallenged(token, issuerNFT, nftId, recipient);
        }

        issuerData.liquidationLocks[token][nftId] = false;

        delete issuerData.issuerLocks[token][nftId];
        delete issuerData.liquidationLockTimes[token][nftId];
        delete issuerData.challengerLocks[token][nftId];
        delete issuerData.challengers[token][nftId];
    }

    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function getDepositAmount(address issuerNFT, uint256 nftId, address token) external view returns (uint256) {
        return issuers[issuerNFT].deposits[token][nftId];
    }

    function isLiquidationLocked(address issuerNFT, uint256 nftId, address token) external view returns (bool) {
        return issuers[issuerNFT].liquidationLocks[token][nftId];
    }

    function getLiquidationLockTime(address issuerNFT, uint256 nftId, address token) external view returns (uint256) {
        return issuers[issuerNFT].liquidationLockTimes[token][nftId];
    }

    function getIssuerLockAmount(address issuerNFT, uint256 nftId, address token) external view returns (uint256) {
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
