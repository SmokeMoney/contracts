// SPDX-License-Identifier: CTOSL
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { console2 } from "forge-std/src/Test.sol"; // TODO REMOVE AFDTRER TEST

import "./interfaces/ICoreNFTContract.sol";
import "./interfaces/IDepositContract.sol";
import "./interfaces/IWstETHOracleReceiver.sol";
import "./interfaces/IAssemblePositionsContract.sol";

contract OperationsContract is EIP712, Ownable, OApp, OAppOptionsType3 {
    using ECDSA for bytes32;

    struct AssemblePositionsBasic {
        address issuerNFT;
        uint256 nftId;
        bool isComplete;
        bool forWithdrawal;
        uint256 timestamp;
        uint256 wstETHRatio;
        address executor;
        uint256 totalAvailableToWithdraw;
        uint256 latestBorrowTimestamp;
    }

    struct WithdrawParams {
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

    bytes32 private constant WITHDRAW_TYPEHASH = keccak256(
        "Withdraw(address issuerNFT,bytes32 token,uint256 nftId,uint256 amount,uint32 targetChainId,uint256 timestamp,uint256 nonce,bool primary,bytes32 recipientAddress)"
    );

    IAssemblePositionsContract public assemblePositionsContract;
    mapping(address => address) public issuers; // issuerNFT -> issuerAddress
    address[] public issuerContracts; // issuerNFT -> issuerAddress
    bool public permissionless;
    uint32 public immutable adminChainId;

    // mapping(uint256 => AssemblePositions) private _assemblePositions;
    mapping(uint256 => IDepositContract) public depositContracts;
    uint256 private _currentAssembleId;
    mapping(uint256 => uint256) public withdrawalNonces;
    mapping(uint256 => uint256) public challengeNonces;

    uint256 public constant SIGNATURE_VALIDITY = 5 minutes;

    event ChainPositionReported(uint256 indexed assembleId, uint256 chainId);
    event ForcedWithdrawalExecuted(uint256 indexed assembleId, bytes32 indexed token, uint256 amount, uint32 targetChainId, bytes32 recipientAddress);
    event AssemblePositionsCreated(uint256 indexed assembleId, uint256 indexed nftId, bool forWithdrawal);
    event CrossChainWithdrawalInitiated(address indexed issuerNFT, uint256 indexed nftId, bytes32 indexed token, uint256 amount, uint32 targetChainId, bytes32 recipientAddress);
    event Withdrawn(address indexed issuerNFT, uint256 indexed nftId, bytes32 indexed token, uint256 amount, uint32 targetChainId);
    event LiquidationChallenged(bytes32 indexed token, uint256 indexed nftId, uint32 targetChainId, address challenger);
    event NewIssuerAdded(address issuerNFT);
    event IssuerChanged(address issuerNFT, address newIssuerAddress);
    event SecondaryWithdrawalAddressSet(address indexed issuerNFT, uint256 indexed nftId, bytes32 withdrawalAddress, uint32 targetChainId);

    constructor(address _endpoint, address _assemblePositionsContract, address _owner, uint32 _adminChainId) 
        OApp(_endpoint, _owner)
        Ownable(_owner)
        EIP712("AccountOperations", "1")
    {
        adminChainId = _adminChainId;
        assemblePositionsContract = IAssemblePositionsContract(_assemblePositionsContract);
        _currentAssembleId = 1;
        permissionless = false;
    }

    modifier onlyIssuer(address issuerNFT) {
        require(issuers[issuerNFT] != address(0), "Invalid issuer");
        require(msg.sender == issuers[issuerNFT], "Not the issuer");
        _;
    }

    function addIssuer(address issuerNFT) external {
        if (!permissionless) {
            require(msg.sender == owner(), 'Sorry, it is permissioned atm');
        }
        require(issuers[issuerNFT] == address(0), "Issuer already exists");
        issuers[issuerNFT] = ICoreNFTContract(issuerNFT).owner();
        issuerContracts.push(issuerNFT);
        emit NewIssuerAdded(issuerNFT);
    }// @attackVector, not being able to remove issuers, is it bad? 

    function changeIssuerAddress(address issuerNFT, address newIssuerAddress) external onlyIssuer(issuerNFT) {
        require(issuers[issuerNFT] != address(0), "Invalid issuer");
        issuers[issuerNFT] = newIssuerAddress;
        emit IssuerChanged(issuerNFT, newIssuerAddress);
    }

    function togglePermission() external onlyOwner {
        permissionless = !permissionless;
    }

    function withdraw(
        WithdrawParams memory params,
        bytes memory signature,
        bytes calldata _extraOptions
    ) external payable {
        require(issuers[params.issuerNFT] != address(0), "Invalid issuer");
        require(ICoreNFTContract(params.issuerNFT).ownerOf(params.nftId) == msg.sender, "Not authorized");
        require(block.timestamp <= params.timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(params.primary, "Invalid withdrawal. Not a secondary port");
        require(params.nonce == withdrawalNonces[params.nftId], "Invalid withdraw nonce");

        _validateWithdrawSignature(params, signature);
        _executeWithdrawal(params.recipientAddress, params.token, params.issuerNFT, params.nftId, params.amount, params.targetChainId, _extraOptions);
    }

    function _validateWithdrawSignature(WithdrawParams memory params, bytes memory signature) internal view {
        
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            WITHDRAW_TYPEHASH,
            params.issuerNFT,
            params.token,
            params.nftId,
            params.amount,
            params.targetChainId,
            params.timestamp,
            params.nonce,
            params.primary,
            params.recipientAddress
        )));
        
        require(
            SignatureChecker.isValidSignatureNow(
                issuers[params.issuerNFT],
                digest,
                signature
            ),
            "Invalid signature from issuer"
        );
    }

    function _executeWithdrawal(bytes32 recipientAddress, bytes32 token, address issuerNFT, uint256 nftId, uint256 amount, uint32 targetChainId, bytes calldata _extraOptions) internal {
        

        if (targetChainId == adminChainId) {
            IDepositContract depositContract = depositContracts[targetChainId];
            require(address(depositContract) != address(0), "Deposit contract not set for this chain");

            depositContract.executeWithdrawal(recipientAddress, token, issuerNFT, nftId, amount);
            emit Withdrawn(issuerNFT, nftId, token, amount, targetChainId);
            withdrawalNonces[nftId]++;
        } else {
            _initiateCrossChainWithdrawal(recipientAddress, token, issuerNFT, nftId, amount, targetChainId, _extraOptions);
        }
    }

    function _initiateCrossChainWithdrawal(bytes32 recipientAddress, bytes32 token, address issuerNFT, uint256 nftId, uint256 amount, uint32 targetChainId, bytes calldata _extraOptions) internal {
        
        // Prepare the payload for the cross-chain message
        bytes memory payload = abi.encode(
            recipientAddress,
            token,
            addressToBytes32(issuerNFT),
            nftId,
            amount
        );

        _lzSend(
            targetChainId,
            encodeMessage(1, payload),
            // encodeMessage(_message, _msgType, _extraReturnOptions),
            _extraOptions,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            payable(msg.sender)
        );
        // Increment the nonce
        withdrawalNonces[nftId]++; 

        emit CrossChainWithdrawalInitiated(issuerNFT, nftId, token, amount, targetChainId, recipientAddress);
    }

    function encodeMessage(uint8 _msgType, bytes memory _payload) public pure returns (bytes memory) {
        // Encode the entire message, prepend and append the length of extraReturnOptions
        return abi.encode(_msgType, _payload);
    }

    function setSecondaryWithdrawalAddress(address issuerNFT, uint256 nftId, bytes32 withdrawalAddress, uint32 targetChainId, bytes calldata _extraOptions ) external payable {
        require(issuers[issuerNFT] != address(0), "Invalid issuer");
        require(ICoreNFTContract(issuerNFT).ownerOf(nftId) == msg.sender, "Not manager or owner for withdrawal");

        bytes memory payload = abi.encode(
            addressToBytes32(issuerNFT),
            nftId,
            withdrawalAddress
        );

        _lzSend(
            targetChainId,
            encodeMessage(3, payload),
            // encodeMessage(_message, _msgType, _extraReturnOptions),
            _extraOptions,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            payable(msg.sender)
        );
        emit SecondaryWithdrawalAddressSet(issuerNFT, nftId, withdrawalAddress, targetChainId);
    }

    function getOnChainReport(uint256 assembleId, address issuerNFT, uint256 nftId, bytes32[] memory wallets, bytes calldata _extraOptions) external {
        IDepositContract depositContract = depositContracts[adminChainId];
        require(address(depositContract) != address(0), "Deposit contract not set for this chain");
        bytes memory _payload = depositContract.reportPositions(assembleId, issuerNFT, nftId, wallets, _extraOptions);
        assemblePositionsContract.setupAssemble(adminChainId, _payload);
        emit ChainPositionReported(assembleId, adminChainId);
    }
    
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _payload,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        uint32 srcChainId = _origin.srcEid;
        uint256 assembleId = assemblePositionsContract.setupAssemble(srcChainId, _payload);
        emit ChainPositionReported(assembleId, srcChainId);
    }

    function isAddressInArray(bytes32[] memory array, bytes32 target) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == target) {
                return true;
            }
        }
        return false;
    }

    function _restoreAssembleOptions(uint256 assembleId) internal view returns (AssemblePositionsBasic memory) {
        (
            address issuerNFT,
            uint256 nftId,
            bool isComplete,
            bool forWithdrawal,
            uint256 timestamp,
            uint256 wstETHRatio,
            address executor,
            uint256 totalAvailableToWithdraw,
            uint256 latestBorrowTimestamp
        ) = assemblePositionsContract.getAssemblePositionsBasic(assembleId);
        // console2.log("issuerNFT: %s | nftId: %s | totalAvailableToWithdraw: %s", issuerNFT, nftId, totalAvailableToWithdraw); // TODO remove after testing

        return AssemblePositionsBasic({
            issuerNFT: issuerNFT,
            nftId: nftId,
            isComplete: isComplete,
            forWithdrawal: forWithdrawal,
            timestamp: timestamp,
            wstETHRatio: wstETHRatio,
            executor: executor,
            totalAvailableToWithdraw: totalAvailableToWithdraw,
            latestBorrowTimestamp: latestBorrowTimestamp
        });
    }
    
    function forcedWithdrawal(uint256 assembleId, bytes32 token, uint256[] memory amounts, uint32[] memory targetChainIds, bytes32 recipientAddress, bytes calldata _extraOptions) external payable {
        AssemblePositionsBasic memory assemble = _restoreAssembleOptions(assembleId);
        ICoreNFTContract nftContract = ICoreNFTContract(assemble.issuerNFT);
        require(!assemble.isComplete, "Assemble already completed");
        require(assemble.forWithdrawal, "Not a withdrawal assemble");
        require(assemble.executor == msg.sender, "Not the preset executor");
        require(nftContract.ownerOf(assemble.nftId) == msg.sender, "Not authorized");

        assemblePositionsContract.verifyAllChainsReported(assembleId);
        // _verifyAllChainsReported(assembleId);

        // check if Ghost NFTs exist and their assemble is present. 
        (uint256 totalBorrowed, uint256 totalCollateral) = assemblePositionsContract.calculateTotatPositionsWithdrawal(assembleId, assemble.nftId);
        // Calculate total available to withdraw
        uint256 maxBorrow = (totalCollateral * nftContract.getLTV() / 10000) + nftContract.getNativeCredit(assemble.nftId); // TODO @attackvector can this be misused? the extra limit I mean
        console2.log("totalBorrowed: %s | maxBorrow: %s | totalCollateral: %s", totalBorrowed, maxBorrow, totalCollateral); // TODO remove after testing

        
        if (assemble.totalAvailableToWithdraw == 0){
            // console2.log("Max Borrow: %s | totalBorrowed: %s | totalCollateral: %s", maxBorrow, totalBorrowed, totalCollateral); // TODO remove after testing
            uint256 totalAvailableToWithdraw = maxBorrow > totalBorrowed ? totalCollateral * (maxBorrow - totalBorrowed) / maxBorrow : 0; // denominated in ETH
            assemblePositionsContract.setTotalAvailableToWithdraw(assembleId, totalAvailableToWithdraw);
        }

        // Execute withdrawals
        _executeWithdrawals(assembleId, token, amounts, targetChainIds, _extraOptions, recipientAddress);

        assemble = _restoreAssembleOptions(assembleId);
        if (assemble.totalAvailableToWithdraw == 0) {
            assemblePositionsContract.markAssembleComplete(assembleId);
        }
    }

    function _executeWithdrawals(uint256 assembleId, bytes32 token, uint256[] memory amounts, uint32[] memory targetChainIds, bytes calldata _extraOptions, bytes32 recipientAddress) internal {
        AssemblePositionsBasic memory assemble = _restoreAssembleOptions(assembleId);
        
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 oracleMultiplier = token == assemblePositionsContract.getAssembleWstETHAddresses(assembleId, targetChainIds[i]) ? assemble.wstETHRatio : 1e18;

            require(assemble.totalAvailableToWithdraw >= amounts[i], "Insufficient funds to withdraw");
            uint256 updatedTotalAvailableToWithdraw = assemble.totalAvailableToWithdraw - amounts[i] * oracleMultiplier / 1e18;
            assemblePositionsContract.setTotalAvailableToWithdraw(assembleId, updatedTotalAvailableToWithdraw);

            _executeWithdrawal(recipientAddress, token, assemble.issuerNFT, assemble.nftId, amounts[i], targetChainIds[i], _extraOptions);

            emit ForcedWithdrawalExecuted(assembleId, token, amounts[i], targetChainIds[i], recipientAddress);
        }
    }

    function liquidationChallenge(uint256 assembleId, bytes32 token, uint32 targetChainId, bytes32 recipientAddress, uint256[] memory gAssembleIds, bytes calldata _extraOptions) external payable {
        AssemblePositionsBasic memory assemble = _restoreAssembleOptions(assembleId);
        require(assemble.executor == msg.sender, "Not the preset executor");

        assemblePositionsContract.verifyAllChainsReported(assembleId);

        (uint256 lowestAssembleTimestamp, uint256 latestBorrowTimestamp) = assemblePositionsContract.calculateTimestamps(assembleId, gAssembleIds);

        assemblePositionsContract.verifyLiquidationThreshold(assembleId, gAssembleIds);

        _executeLiquidationChallenge(token, assemble.issuerNFT, assemble.nftId, lowestAssembleTimestamp, latestBorrowTimestamp, recipientAddress, targetChainId, _extraOptions);

        emit LiquidationChallenged(token, assemble.nftId, targetChainId, msg.sender);
    }

    function _executeLiquidationChallenge(bytes32 token, address issuerNFT, uint256 nftId, uint256 lowestAssembleTimestamp, uint256 latestBorrowTimestamp, bytes32 recipientAddress, uint32 targetChainId, bytes calldata _extraOptions) internal {
        if (targetChainId == adminChainId) {
            IDepositContract depositContract = depositContracts[targetChainId];
            require(address(depositContract) != address(0), "Deposit contract not set for this chain");
            depositContract.onChainLiqChallenge(addressToBytes32(issuerNFT), nftId, token, lowestAssembleTimestamp, latestBorrowTimestamp, recipientAddress);
            challengeNonces[nftId]++;
        } else {
            _initiateCrossChainChallenge(token, issuerNFT, nftId, lowestAssembleTimestamp, latestBorrowTimestamp, recipientAddress, targetChainId, _extraOptions);
        }
    }

    function _initiateCrossChainChallenge(bytes32 token, address issuerNFT, uint256 nftId, uint256 assembleTimestamp, uint256 latestBorrowTimestamp, bytes32 recipientAddress, uint32 targetChainId, bytes calldata _extraOptions) internal {
        
        // Prepare the payload for the cross-chain message
        bytes memory payload = abi.encode(
            recipientAddress,
            token,
            addressToBytes32(issuerNFT),
            nftId,
            assembleTimestamp,
            latestBorrowTimestamp,
            challengeNonces[nftId]
        );

        _lzSend(
            targetChainId,
            encodeMessage(2, payload),
            // encodeMessage(_message, _msgType, _extraReturnOptions),
            _extraOptions,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            payable(msg.sender)
        );
        // Increment the nonce
        challengeNonces[nftId]++;
    }

    function setDepositContract(uint256 chainId, address contractAddress) external onlyOwner {
        require(address(depositContracts[chainId]) == address(0), "Deposit contract already set for this chain");
        depositContracts[chainId] = IDepositContract(contractAddress);
    }

    function setNewIssuer(address issuerNFT, address newIssuer) external onlyIssuer(issuerNFT) {
        issuers[issuerNFT] = newIssuer;
    }

    function quote(
        uint32 targetChainId,
        uint16 _msgType,
        bytes calldata payload,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {

        fee = _quote(targetChainId, payload, _extraOptions, _payInLzToken);
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