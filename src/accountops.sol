// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import { console2 } from "forge-std/Test.sol"; // TODO REMOVE AFDTRER TEST


interface ICoreNFTContract {
    function ownerOf(uint256 nftId) external view returns (address);
    function isManagerOrOwner(uint256 nftId, address addr) external view returns (bool);
    function isWalletAdded(uint256 nftId, address wallet) external view returns (bool);
    function getWallets(uint256 nftId) external view returns (address[] memory);
    function getWalletChainLimit(uint256 nftId, address wallet, uint256 chainId) external view returns (uint256);
    function getWalletsWithLimitChain(uint256 nftId, uint256 chainId) external view returns (address[] memory);
    function getExtraLimit(uint256 nftId) external view returns (uint256);
    function getChainList() external view returns (uint256[] memory);
}

interface IDepositContract {
    function executeWithdrawal(address user, address token, uint256 nftId, uint256 amount) external;
    function reportPositions(uint256 assembleId, uint256 nftId, address[] memory wallets, bytes calldata _extraOptions) external payable returns (bytes memory);
    function onChainLiqChallenge(address token, uint256 nftId, uint256 assembleTimestamp, uint256 latestBorrowTimestamp, address recipient) external;
}

contract OperationsContract is Ownable, OApp, OAppOptionsType3 {
    using ECDSA for bytes32;

    struct AssemblePositions {
        uint256 nftId;
        mapping(uint256 => bool) chainReported;
        mapping(uint256 => mapping(address => uint256)) borrowPositions; // chainID -> wallet -> position
        mapping(uint256 => uint256) depositPositions;
        mapping(uint256 => uint256) wstETHDepositPositions;
        mapping(uint256 => address) wethAddresses;
        mapping(uint256 => address) wstETHAddresses;
        uint256 totalAvailableToWithdraw;
        bool isComplete;
        bool forWithdrawal;
        uint256 timestamp;
        uint256 wstETHRatio;
        address executor;
        uint256 latestBorrowTimestamp;
    }

    struct AssembleData {
        uint256 assembleId;
        uint256 nftId;
        uint256 depositAmount;
        uint256 wstETHDepositAmount;
        address wethAddress;
        address wstETHAddress;
    }
    
    struct WalletData {
        address[] wallets;
        uint256[] borrowAmounts;
        uint256[] interestAmounts;
        uint256 latestBorrowTimestamp;
    }

    ICoreNFTContract public coreNFTContract;
    IPyth public pyth;
    address public issuer;
    uint32 public immutable adminChainId;
    mapping(uint256 => AssemblePositions) private _assemblePositions;
    mapping(uint256 => uint256) public currentIncompleteWithdrawalAssembleIds; // nftID -> AssembleID
    mapping(uint256 => IDepositContract) public depositContracts;
    uint256 private _currentAssembleId;
    mapping(uint256 => uint256) public withdrawalNonces;
    mapping(uint256 => uint256) public challengeNonces;

    uint256 public constant LTV_RATIO = 90; // 90% LTV ratio
    uint256 public constant LIQ_THRESHOLD = 95; // 95% LTV ratio
    uint256 public constant SIGNATURE_VALIDITY = 5 minutes;
    uint256 public constant ASSEMBLE_VALID_FOR = 24 hours;

    event ChainPositionReported(uint256 indexed assembleId, uint256 chainId);
    event ForcedWithdrawalExecuted(uint256 indexed assembleId, address indexed token, uint256 amount, uint32 targetChainId, address recipientAddress);
    event AssemblePositionsCreated(uint256 indexed assembleId, uint256 indexed nftId, bool forWithdrawal);
    event CrossChainWithdrawalInitiated(uint256 indexed nftId, address indexed token, uint256 amount, uint32 targetChainId, address recipientAddress);
    event Withdrawn(uint256 indexed nftId, address indexed token, uint256 amount, uint32 targetChainId);
    event LiquidationChallenged(address indexed token, uint256 indexed nftId, uint32 targetChainId, address challenger);

    constructor(address _coreNFTContract, address _endpoint, address _pythContract, address _issuer, address _owner, uint32 _adminChainId) 
        OApp(_endpoint, _owner)
        Ownable(_owner)
    {
        issuer = _issuer;
        coreNFTContract = ICoreNFTContract(_coreNFTContract);
        pyth = IPyth(_pythContract);
        adminChainId = _adminChainId;
        _currentAssembleId = 1;
    }

    modifier onlyIssuer() {
        require(msg.sender == issuer, "Not the issuer");
        _;
    }

    function withdraw(
        address token,
        uint256 nftId,
        uint256 amount,
        uint32 targetChainId,
        uint256 timestamp,
        uint256 nonce,
        bytes memory signature,
        bytes calldata _extraOptions, 
        address recipientAddress
    ) external payable {
        require(coreNFTContract.isManagerOrOwner(nftId, msg.sender), "Not authorized");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        if (withdrawalNonces[nftId]==0) {
            withdrawalNonces[nftId] = 1; //it always starts with 1
        }
        require(nonce == withdrawalNonces[nftId], "Invalid withdraw nonce");

        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, token, nftId, amount, targetChainId, timestamp, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuer, "Invalid withdraw signature");

        _executeWithdrawal(recipientAddress, token, nftId, amount, targetChainId, _extraOptions);
    }

    function _executeWithdrawal(address recipientAddress, address token, uint256 nftId, uint256 amount, uint32 targetChainId, bytes calldata _extraOptions) internal {
        if (targetChainId == adminChainId) {
            IDepositContract depositContract = depositContracts[targetChainId];
            require(address(depositContract) != address(0), "Deposit contract not set for this chain");
            depositContract.executeWithdrawal(recipientAddress, token, nftId, amount);
            emit Withdrawn(nftId, token, amount, targetChainId);
            withdrawalNonces[nftId]++;
        } else {
            _initiateCrossChainWithdrawal(recipientAddress, token, nftId, amount, targetChainId, _extraOptions);
        }
    }

    function _initiateCrossChainWithdrawal(address recipientAddress, address token, uint256 nftId, uint256 amount, uint32 targetChainId, bytes calldata _extraOptions) internal {
        
        // Prepare the payload for the cross-chain message
        bytes memory payload = abi.encode(
            recipientAddress,
            token,
            nftId,
            amount,
            withdrawalNonces[nftId]
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

        emit CrossChainWithdrawalInitiated(nftId, token, amount, targetChainId, recipientAddress);
    }

    function encodeMessage(uint8 _msgType, bytes memory _payload) public pure returns (bytes memory) {

        // Encode the entire message, prepend and append the length of extraReturnOptions
        return abi.encode(_msgType, _payload);
    }

    function createAssemblePositions(uint256 nftId, bool forWithdrawal, address executor, bytes[] calldata priceUpdate) external payable returns (uint256) {
        require(forWithdrawal == false || coreNFTContract.isManagerOrOwner(nftId, msg.sender), "Not manager or owner for withdrawal");
        
        if (forWithdrawal) {
            uint256 currentIncompleteAssembleId = currentIncompleteWithdrawalAssembleIds[nftId];
            require(currentIncompleteAssembleId == 0 || _assemblePositions[currentIncompleteAssembleId].isComplete, 
                    "An incomplete withdrawal assemble already exists for this NFT");
        }

        uint256 assembleId = _currentAssembleId;
        _currentAssembleId++;
        AssemblePositions storage newAssemble = _assemblePositions[assembleId];
        newAssemble.nftId = nftId;
        newAssemble.forWithdrawal = forWithdrawal;
        newAssemble.timestamp = block.timestamp;
        newAssemble.executor = executor;

        if (forWithdrawal) {
            currentIncompleteWithdrawalAssembleIds[nftId] = assembleId;
        }

        uint fee = pyth.getUpdateFee(priceUpdate);
        pyth.updatePriceFeeds{ value: fee }(priceUpdate);
    
        bytes32 priceFeedIdETH = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace; // ETH/USD
        bytes32 priceFeedIdwstETH = 0x6df640f3b8963d8f8358f791f352b8364513f6ab1cca5ed3f1f7b5448980e784; // wstETH/USD
        PythStructs.Price memory ETHPrice = pyth.getPrice(priceFeedIdETH);
        PythStructs.Price memory wstETHPrice = pyth.getPrice(priceFeedIdwstETH);    
    
        newAssemble.wstETHRatio = safeConvertInt64ToUint256(wstETHPrice.price)*1e18/safeConvertInt64ToUint256(ETHPrice.price);

        emit AssemblePositionsCreated(assembleId, nftId, forWithdrawal);

        return assembleId;
    }

    function safeConvertInt64ToUint256(int64 value) internal pure returns (uint256) {
        require(value >= 0, "Cannot convert negative int64 to uint256");
        return uint256(uint64(value));
    }

    function getOnChainReport(uint256 assembleId, uint256 nftId, address[] memory wallets, bytes calldata _extraOptions) external {
        IDepositContract depositContract = depositContracts[adminChainId];
        require(address(depositContract) != address(0), "Deposit contract not set for this chain");
        bytes memory _payload = depositContract.reportPositions(assembleId, nftId, wallets, _extraOptions);
        _setupAssemble(adminChainId, _payload);
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
        uint256 assembleId = _setupAssemble(srcChainId, _payload);
        emit ChainPositionReported(assembleId, srcChainId);
    }

    function _setupAssemble(uint32 srcChainId, bytes memory _payload) internal returns (uint256) {
        (AssembleData memory assembleData, WalletData memory walletData) = _decodeAssemblePayload(_payload);
    
        AssemblePositions storage assemble = _assemblePositions[assembleData.assembleId];
        
        require(assemble.nftId == assembleData.nftId, "Invalid NFT ID");
        require(!assemble.chainReported[srcChainId], "Chain already reported");
    
        assemble.chainReported[srcChainId] = true;
        assemble.depositPositions[srcChainId] = assembleData.depositAmount;
        assemble.wstETHDepositPositions[srcChainId] = assembleData.wstETHDepositAmount;
        assemble.wethAddresses[srcChainId] = assembleData.wethAddress;
        assemble.wstETHAddresses[srcChainId] = assembleData.wstETHAddress;
        assemble.latestBorrowTimestamp = assemble.latestBorrowTimestamp > walletData.latestBorrowTimestamp ? assemble.latestBorrowTimestamp : walletData.latestBorrowTimestamp;

        address[] memory walletsReqChain = coreNFTContract.getWalletsWithLimitChain(assembleData.nftId, uint256(srcChainId));

        require(walletData.wallets.length == walletsReqChain.length, "Wallet list length mismatch");
        for (uint256 i = 0; i < walletsReqChain.length; i++) {
            require(isAddressInArray(walletData.wallets, walletsReqChain[i]), "Wallet lists do not match");
        }
    
        for (uint256 i = 0; i < walletData.wallets.length; i++) {
            uint256 approvedLimit = coreNFTContract.getWalletChainLimit(assembleData.nftId, walletData.wallets[i], srcChainId);
            uint256 validBorrowAmount = walletData.borrowAmounts[i] > approvedLimit ? approvedLimit + walletData.interestAmounts[i] : walletData.borrowAmounts[i] + walletData.interestAmounts[i];
            assemble.borrowPositions[srcChainId][walletData.wallets[i]] = validBorrowAmount;
        }

        return assembleData.assembleId;
    }

    function isAddressInArray(address[] memory array, address target) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == target) {
                return true;
            }
        }
        return false;
    }
    
    function _decodeAssemblePayload(bytes memory _payload) private pure returns (AssembleData memory, WalletData memory) {
        (
            uint256 assembleId,
            uint256 nftId,
            uint256 depositAmount,
            uint256 wstETHDepositAmount,
            address wethAddress,
            address wstETHAddress,
            uint256 latestBorrowTimestamp,
            address[] memory wallets,
            uint256[] memory borrowAmounts,
            uint256[] memory interestAmounts
        ) = abi.decode(_payload, (uint256, uint256, uint256, uint256, address, address, uint256, address[], uint256[], uint256[]));
    
        return (
            AssembleData(assembleId, nftId, depositAmount, wstETHDepositAmount, wethAddress, wstETHAddress),
            WalletData(wallets, borrowAmounts, interestAmounts, latestBorrowTimestamp)
        );
    }
    
    function forcedWithdrawal(uint256 assembleId, address token, uint256[] memory amounts, uint32[] memory targetChainIds, bytes calldata _extraOptions, address recipientAddress) external payable {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        require(!assemble.isComplete, "Assemble already completed");
        require(assemble.forWithdrawal, "Not a withdrawal assemble");
        require(assemble.executor == msg.sender, "Not the preset executor");
        require(coreNFTContract.isManagerOrOwner(assemble.nftId, msg.sender), "Not authorized");

        uint256[] memory chainList = coreNFTContract.getChainList();
        // Verify all chains have reported TODO only positive limit chains need to be reported
        for (uint256 i = 0; i < chainList.length; i++) {
            address[] memory walletsWithPostitiveLimit = coreNFTContract.getWalletsWithLimitChain(assemble.nftId, chainList[i]);
            if (walletsWithPostitiveLimit.length > 0) {
                require(assemble.chainReported[chainList[i]], "Not all chains have reported");
            }
        }

        // Calculate total borrow and deposit positions
        (uint256 totalBorrowed, uint256 totalCollateral) = _calculateTotalPositions(assembleId);

        // Calculate total available to withdraw
        uint256 maxBorrow = (totalCollateral * LTV_RATIO / 100) + coreNFTContract.getExtraLimit(assemble.nftId); // TODO @attackvector can this be misused? the extra limit I mean
        
        
        if (assemble.totalAvailableToWithdraw == 0){

            console2.log("Max Borrow: %s | totalBorrowed: %s | totalCollateral: %s", maxBorrow, totalBorrowed, totalCollateral); // TODO remove after testing
            assemble.totalAvailableToWithdraw = maxBorrow > totalBorrowed ? totalCollateral * (maxBorrow - totalBorrowed) / maxBorrow : 0; // denominated in ETH
        }
        
        // Execute withdrawals
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 oracleMultiplier = token == assemble.wethAddresses[targetChainIds[i]] ? 1e18 : assemble.wstETHRatio;

            require(assemble.totalAvailableToWithdraw >= amounts[i], "Insufficient funds to withdraw");
            assemble.totalAvailableToWithdraw -= amounts[i] * oracleMultiplier / 1e18;

            _executeWithdrawal(recipientAddress, token, assemble.nftId, amounts[i], targetChainIds[i], _extraOptions);

            emit ForcedWithdrawalExecuted(assembleId, token, amounts[i], targetChainIds[i], recipientAddress);
        }

        if (assemble.totalAvailableToWithdraw == 0) {
            assemble.isComplete = true;

            if (assembleId == currentIncompleteWithdrawalAssembleIds[assemble.nftId]) {
                currentIncompleteWithdrawalAssembleIds[assemble.nftId] = 0;
            }
        }
    }

    function _calculateTotalPositions(uint256 assembleId) internal view returns (uint256 totalBorrowed, uint256 totalDeposited) {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        address[] memory wallets = coreNFTContract.getWallets(assemble.nftId);

        uint256[] memory chainList = coreNFTContract.getChainList();
        for (uint256 j = 0; j < chainList.length; j++) {
            totalDeposited += assemble.depositPositions[chainList[j]];
            totalDeposited += assemble.wstETHDepositPositions[chainList[j]] * assemble.wstETHRatio / 1e18;
            for (uint256 i = 0; i < wallets.length; i++) {
                // console2.log(
                //     "Chain: %s | Wallet: %s | Borrow: %s",
                //     chainList[j],
                //     wallets[i],
                //     assemble.borrowPositions[chainList[j]][wallets[i]]
                // ); # TODO remove after testing
                totalBorrowed += assemble.borrowPositions[chainList[j]][wallets[i]];            
            }
        }
    }

    function liquidationChallenge(uint256 assembleId, address token, uint32 targetChainId, address recipientAddress, bytes calldata _extraOptions) external payable {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        require(assemble.executor == msg.sender, "Not the present executor");

        uint256[] memory chainList = coreNFTContract.getChainList();
        // Verify all chains have reported TODO only positive limit chains need to be reported
        for (uint256 i = 0; i < chainList.length; i++) {
            address[] memory walletsWithPostitiveLimit = coreNFTContract.getWalletsWithLimitChain(assemble.nftId, chainList[i]);
            if (walletsWithPostitiveLimit.length > 0) {
                require(assemble.chainReported[chainList[i]], "Not all chains have reported");
            }
        }
        // Calculate total borrow and deposit positions
        (uint256 totalBorrowed, uint256 totalCollateral) = _calculateTotalPositions(assembleId);

        // Calculate total available to withdraw
        uint256 liqThreshold = (totalCollateral * LIQ_THRESHOLD / 100) + coreNFTContract.getExtraLimit(assemble.nftId); // TODO @attackvector can this be misused? the extra limit I mean
        
        require(totalBorrowed < liqThreshold, "Borrow position is above the liquidation threshold");

        console2.log("Total borrowed: %s | Liq Threshold: %s", totalBorrowed, liqThreshold); // TODO remove after testing

        if (targetChainId == adminChainId) {
            IDepositContract depositContract = depositContracts[targetChainId];
            require(address(depositContract) != address(0), "Deposit contract not set for this chain");
            depositContract.onChainLiqChallenge(token, assemble.nftId, assemble.timestamp, assemble.latestBorrowTimestamp, recipientAddress);
            challengeNonces[assemble.nftId]++;
        } else {
            _initiateCrossChainChallenge(token, assemble.nftId, assemble.timestamp, assemble.latestBorrowTimestamp, recipientAddress, targetChainId, _extraOptions);
        }

        emit LiquidationChallenged(token, assemble.nftId, targetChainId, msg.sender);

    }

    function _initiateCrossChainChallenge(address token, uint256 nftId, uint256 assembleTimestamp, uint256 latestBorrowTimestamp, address recipientAddress, uint32 targetChainId, bytes calldata _extraOptions) internal {
        
        // Prepare the payload for the cross-chain message
        bytes memory payload = abi.encode(
            recipientAddress,
            token,
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

    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function getWithdrawNonce(uint256 nftId) external view returns (uint256) {
        return withdrawalNonces[nftId];
    }

    function getAssembleChainsReported(uint256 assembleId) external view returns (uint256) {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        uint256 reportedChains = 0;

        uint256[] memory chainList = coreNFTContract.getChainList();
        for (uint256 i = 0; i < chainList.length; i++) {
            if (assemble.chainReported[chainList[i]]) {
                reportedChains++;
            }
        }
        return reportedChains;
    }

    function setDepositContract(uint256 chainId, address contractAddress) external onlyIssuer {
        require(address(depositContracts[chainId]) == address(0), "Deposit contract already set for this chain");
        depositContracts[chainId] = IDepositContract(contractAddress);
    }

    function setNewIssuer(address newIssuer) external onlyIssuer {
        issuer = newIssuer;
    }

    function hasIncompleteWithdrawalAssemble(uint256 nftId) public view returns (bool) {
        uint256 assembleId = currentIncompleteWithdrawalAssembleIds[nftId];
        return assembleId != 0 && !_assemblePositions[assembleId].isComplete;
    }

    function markAssembleComplete(uint256 assembleId) external {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        require(coreNFTContract.isManagerOrOwner(assemble.nftId, msg.sender), "Not authorized");
        assemble.isComplete = true;

        if (assemble.forWithdrawal && assembleId == currentIncompleteWithdrawalAssembleIds[assemble.nftId]) {
            currentIncompleteWithdrawalAssembleIds[assemble.nftId] = 0;
        }
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
}