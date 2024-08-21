// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
// import { console2 } from "forge-std/Test.sol"; // TODO REMOVE AFDTRER TEST


interface ICoreNFTContract {
    struct GNFTWallet {
        uint256 gNFT;
        bytes32 gWallet;
    }

    function ownerOf(uint256 nftId) external view returns (address);
    function isManagerOrOwner(uint256 nftId, address addr) external view returns (bool);
    function isWalletAdded(uint256 nftId, bytes32 wallet) external view returns (bool);
    function getWallets(uint256 nftId) external view returns (bytes32[] memory);
    function getGNFTList(uint256 nftId) external view returns (uint256[] memory);
    function getPWalletsTotalLimit(uint256 nftId) external view returns (uint256);
    function getGWallet(uint256 gNFT) external view returns (bytes32);
    function getWalletChainLimit(uint256 nftId, bytes32 wallet, uint256 chainId) external view returns (uint256);
    function getWalletsWithLimitChain(uint256 nftId, uint256 chainId) external view returns (bytes32[] memory);
    function getExtraLimit(uint256 nftId) external view returns (uint256);
    function getChainList() external view returns (uint256[] memory);
    function owner() external view returns (address);
    function getGNFTCount(uint256 nftId) external view returns (uint256);
    function getTotalSupply() external pure returns (uint256);
}

interface IDepositContract {
    function executeWithdrawal(bytes32 user, bytes32 token, address issuerNFT, uint256 nftId, uint256 amount) external;
    function reportPositions(uint256 assembleId, address issuerNFT, uint256 nftId, bytes32[] memory wallets, bytes calldata _extraOptions) external payable returns (bytes memory);
    function onChainLiqChallenge(bytes32 token, bytes32 issuerNFT, uint256 nftId, uint256 assembleTimestamp, uint256 latestBorrowTimestamp, bytes32 recipient) external;
}

interface IWstETHOracleReceiver {
    function getLastUpdatedRatio() external view returns (uint256, uint256);
}

contract OperationsContract is Ownable, OApp, OAppOptionsType3 {
    using ECDSA for bytes32;

    struct AssemblePositions {
        address issuerNFT;
        uint256 nftId;
        mapping(uint256 => bool) chainReported;
        mapping(uint256 => mapping(bytes32 => uint256)) borrowPositions; // chainID -> wallet -> position
        mapping(uint256 => uint256) depositPositions;
        mapping(uint256 => uint256) wstETHDepositPositions;
        mapping(uint256 => bytes32) wethAddresses;
        mapping(uint256 => bytes32) wstETHAddresses;
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
        address issuerNFT;
        uint256 nftId;
        uint256 depositAmount;
        uint256 wstETHDepositAmount;
        bytes32 wethAddress;
        bytes32 wstETHAddress;
    }
    
    struct WalletData {
        bytes32[] wallets;
        uint256[] borrowAmounts;
        uint256[] interestAmounts;
        uint256 latestBorrowTimestamp;
    }

    struct GNFTWallet {
        uint256 gNFT;
        bytes32 gWallet;
    }

    ICoreNFTContract public coreNFTContract;
    IWstETHOracleReceiver public wstETHOracle;
    mapping(address => address) public issuers; // issuerNFT -> issuerAddress
    address[] public issuerContracts; // issuerNFT -> issuerAddress
    bool public permissionless;
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
    event ForcedWithdrawalExecuted(uint256 indexed assembleId, bytes32 indexed token, uint256 amount, uint32 targetChainId, bytes32 recipientAddress);
    event AssemblePositionsCreated(uint256 indexed assembleId, uint256 indexed nftId, bool forWithdrawal);
    event CrossChainWithdrawalInitiated(address indexed issuerNFT, uint256 indexed nftId, bytes32 indexed token, uint256 amount, uint32 targetChainId, bytes32 recipientAddress);
    event Withdrawn(address indexed issuerNFT, uint256 indexed nftId, bytes32 indexed token, uint256 amount, uint32 targetChainId);
    event LiquidationChallenged(bytes32 indexed token, uint256 indexed nftId, uint32 targetChainId, address challenger);
    event NewIssuerAdded(address issuerNFT);
    event IssuerRemoved(address issuerNFT);
    event SecondaryWithdrawalAddressSet(address indexed issuerNFT, uint256 indexed nftId, bytes32 withdrawalAddress, uint32 targetChainId);

    constructor(address _coreNFTContract, address _endpoint, address _wstETHOracleContract, address _owner, uint32 _adminChainId) 
        OApp(_endpoint, _owner)
        Ownable(_owner)
    {
        coreNFTContract = ICoreNFTContract(_coreNFTContract);
        adminChainId = _adminChainId;
        wstETHOracle = IWstETHOracleReceiver(_wstETHOracleContract);
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
    }

    function removeIssuer(address issuerNFT) external {
        if (!permissionless) {
            require(msg.sender == owner(), 'Sorry, it is permissioned atm');
        }
        require(issuers[issuerNFT] != address(0), "Invalid issuer");
        issuers[issuerNFT] = address(0);
        emit NewIssuerAdded(issuerNFT);
    }

    function togglePermission() external onlyOwner {
        permissionless = !permissionless;
    }

    function withdraw(
        address issuerNFT,
        bytes32 token,
        uint256 nftId,
        uint256 amount,
        uint32 targetChainId,
        uint256 timestamp,
        uint256 nonce,
        bool primary,
        bytes memory signature,
        bytes calldata _extraOptions, 
        bytes32 recipientAddress
    ) external payable {
        require(issuers[issuerNFT] != address(0), "Invalid issuer");
        require(ICoreNFTContract(issuerNFT).isManagerOrOwner(nftId, msg.sender), "Not authorized");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(primary, "Invalid withdrawal. Not a secondary port");

        require(nonce == withdrawalNonces[nftId], "Invalid withdraw nonce");

        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, issuerNFT, token, nftId, amount, targetChainId, timestamp, nonce, primary));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuers[issuerNFT], "Invalid withdraw signature");

        _executeWithdrawal(recipientAddress, token, issuerNFT, nftId, amount, targetChainId, _extraOptions);
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
        require(ICoreNFTContract(issuerNFT).isManagerOrOwner(nftId, msg.sender), "Not manager or owner for withdrawal");

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

    function createAssemblePositions(address issuerNFT, uint256 nftId, bool forWithdrawal, address executor) external returns (uint256) {
        require(issuers[issuerNFT] != address(0), "Invalid issuer");
        require(forWithdrawal == false || ICoreNFTContract(issuerNFT).isManagerOrOwner(nftId, msg.sender) || nftId > ICoreNFTContract(issuerNFT).getTotalSupply(), "Not manager or owner for withdrawal");
        
        if (forWithdrawal) {
            uint256 currentIncompleteAssembleId = currentIncompleteWithdrawalAssembleIds[nftId];
            require(currentIncompleteAssembleId == 0 || _assemblePositions[currentIncompleteAssembleId].isComplete, 
                    "An incomplete withdrawal assemble already exists for this NFT");
        }

        uint256 assembleId = _currentAssembleId;
        _currentAssembleId++;
        AssemblePositions storage newAssemble = _assemblePositions[assembleId];
        newAssemble.issuerNFT = issuerNFT;
        newAssemble.nftId = nftId;
        newAssemble.forWithdrawal = forWithdrawal;
        newAssemble.timestamp = block.timestamp;
        newAssemble.executor = executor;

        if (forWithdrawal) {
            currentIncompleteWithdrawalAssembleIds[nftId] = assembleId;
        }

        uint256 lastUpdateTimestamp;
        (newAssemble.wstETHRatio, lastUpdateTimestamp) = wstETHOracle.getLastUpdatedRatio();
        require(block.timestamp - lastUpdateTimestamp < 12 hours, 'Last oracle update is too old, pls refresh');

        emit AssemblePositionsCreated(assembleId, nftId, forWithdrawal);

        return assembleId;
    }

    function safeConvertInt64ToUint256(int64 value) internal pure returns (uint256) {
        require(value >= 0, "Cannot convert negative int64 to uint256");
        return uint256(uint64(value));
    }

    function getOnChainReport(uint256 assembleId, address issuerNFT, uint256 nftId, bytes32[] memory wallets, bytes calldata _extraOptions) external {
        IDepositContract depositContract = depositContracts[adminChainId];
        require(address(depositContract) != address(0), "Deposit contract not set for this chain");
        bytes memory _payload = depositContract.reportPositions(assembleId, issuerNFT, nftId, wallets, _extraOptions);
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

        
        require(assemble.issuerNFT == assembleData.issuerNFT, "Invalid Issuer ID");
        require(assemble.nftId == assembleData.nftId, "Invalid NFT ID");
        require(!assemble.chainReported[srcChainId], "Chain already reported");
    
        ICoreNFTContract nftContract = ICoreNFTContract(assemble.issuerNFT);

        assemble.chainReported[srcChainId] = true;
        assemble.depositPositions[srcChainId] = assembleData.depositAmount;
        assemble.wstETHDepositPositions[srcChainId] = assembleData.wstETHDepositAmount;
        assemble.wethAddresses[srcChainId] = assembleData.wethAddress;
        assemble.wstETHAddresses[srcChainId] = assembleData.wstETHAddress;
        assemble.latestBorrowTimestamp = assemble.latestBorrowTimestamp > walletData.latestBorrowTimestamp ? assemble.latestBorrowTimestamp : walletData.latestBorrowTimestamp;

        bool gNFT = assemble.nftId > ICoreNFTContract(assemble.issuerNFT).getTotalSupply();
        if (gNFT) {
            bytes32 gWallet = nftContract.getGWallet(assemble.nftId);
            require(isAddressInArray(walletData.wallets, gWallet), "GWallet does not exist");
            for (uint256 i = 0; i < walletData.wallets.length; i++) {
                uint256 approvedLimit = nftContract.getWalletChainLimit(assembleData.nftId, walletData.wallets[i], srcChainId);
                uint256 validBorrowAmount = walletData.borrowAmounts[i] > approvedLimit ? approvedLimit + walletData.interestAmounts[i] : walletData.borrowAmounts[i] + walletData.interestAmounts[i];
                assemble.borrowPositions[srcChainId][walletData.wallets[i]] = validBorrowAmount;
            }
        }
        else {
            bytes32[] memory walletsReqChain = nftContract.getWalletsWithLimitChain(assembleData.nftId, uint256(srcChainId));

            require(walletData.wallets.length == walletsReqChain.length || gNFT, "Wallet list length mismatch");
            for (uint256 i = 0; i < walletsReqChain.length; i++) {
                require(isAddressInArray(walletData.wallets, walletsReqChain[i]), "Wallet lists do not match");
            }
        
            for (uint256 i = 0; i < walletData.wallets.length; i++) {
                uint256 approvedLimit = nftContract.getWalletChainLimit(assembleData.nftId, walletData.wallets[i], srcChainId);
                uint256 validBorrowAmount = walletData.borrowAmounts[i] > approvedLimit ? approvedLimit + walletData.interestAmounts[i] : walletData.borrowAmounts[i] + walletData.interestAmounts[i];
                assemble.borrowPositions[srcChainId][walletData.wallets[i]] = validBorrowAmount;
            }
        }

        return assembleData.assembleId;
    }

    function isAddressInArray(bytes32[] memory array, bytes32 target) internal pure returns (bool) {
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
            bytes32 issuerNFT,
            uint256 nftId,
            uint256 depositAmount,
            uint256 wstETHDepositAmount,
            bytes32 wethAddress,
            bytes32 wstETHAddress,
            uint256 latestBorrowTimestamp,
            bytes32[] memory wallets,
            uint256[] memory borrowAmounts,
            uint256[] memory interestAmounts
        ) = abi.decode(_payload, (uint256, bytes32, uint256, uint256, uint256, bytes32, bytes32, uint256, bytes32[], uint256[], uint256[]));
    
        return (
            AssembleData(assembleId, bytes32ToAddress(issuerNFT), nftId, depositAmount, wstETHDepositAmount, wethAddress, wstETHAddress),
            WalletData(wallets, borrowAmounts, interestAmounts, latestBorrowTimestamp)
        );
    }
    
    function forcedWithdrawal(uint256 assembleId, bytes32 token, uint256[] memory amounts, uint32[] memory targetChainIds, bytes calldata _extraOptions, bytes32 recipientAddress) external payable {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        
        ICoreNFTContract nftContract = ICoreNFTContract(assemble.issuerNFT);
        require(!assemble.isComplete, "Assemble already completed");
        require(assemble.forWithdrawal, "Not a withdrawal assemble");
        require(assemble.executor == msg.sender, "Not the preset executor");
        require(nftContract.isManagerOrOwner(assemble.nftId, msg.sender), "Not authorized");

        uint256[] memory chainList = nftContract.getChainList();
        // Verify all chains have reported TODO only positive limit chains need to be reported
        for (uint256 i = 0; i < chainList.length; i++) {
            bytes32[] memory walletsWithPostitiveLimit = nftContract.getWalletsWithLimitChain(assemble.nftId, chainList[i]);
            if (walletsWithPostitiveLimit.length > 0) {
                require(assemble.chainReported[chainList[i]], "Not all chains have reported");
            }
        }

        // check if Ghost NFTs exist and their assemble is present. 
        uint256 gNFTCount = nftContract.getGNFTCount(assemble.nftId);
        uint256 gTotalBorrowed;
        uint256 gTotalCollateral;
        if ( gNFTCount > 0) {
            uint256[] memory gNFTList = nftContract.getGNFTList(assemble.nftId);
            for (uint256 i = 0; i<gNFTList.length; i++){
                uint256 gAssembleId = currentIncompleteWithdrawalAssembleIds[gNFTList[i]];
                require(gAssembleId != 0, "GAssemble doesnt exist");
                (uint256 gBorrowed, uint256 gCollateral) = _calculateTotalPositions(gAssembleId);
                gTotalBorrowed += gBorrowed;
                gTotalCollateral += gCollateral;
            }
            gTotalBorrowed += nftContract.getPWalletsTotalLimit(assemble.nftId);
        }

        // Calculate total borrow and deposit positions
        (uint256 totalBorrowed, uint256 totalCollateral) = _calculateTotalPositions(assembleId);
        totalBorrowed += gTotalBorrowed;
        totalCollateral += gTotalCollateral;
        // Calculate total available to withdraw
        uint256 maxBorrow = (totalCollateral * LTV_RATIO / 100) + nftContract.getExtraLimit(assemble.nftId); // TODO @attackvector can this be misused? the extra limit I mean
        
        
        if (assemble.totalAvailableToWithdraw == 0){

            // console2.log("Max Borrow: %s | totalBorrowed: %s | totalCollateral: %s", maxBorrow, totalBorrowed, totalCollateral); // TODO remove after testing
            assemble.totalAvailableToWithdraw = maxBorrow > totalBorrowed ? totalCollateral * (maxBorrow - totalBorrowed) / maxBorrow : 0; // denominated in ETH
        }
        
        // Execute withdrawals
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 oracleMultiplier = token == assemble.wethAddresses[targetChainIds[i]] ? 1e18 : assemble.wstETHRatio;

            require(assemble.totalAvailableToWithdraw >= amounts[i], "Insufficient funds to withdraw");
            assemble.totalAvailableToWithdraw -= amounts[i] * oracleMultiplier / 1e18;

            _executeWithdrawal(recipientAddress, token, assemble.issuerNFT, assemble.nftId, amounts[i], targetChainIds[i], _extraOptions);

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
        ICoreNFTContract nftContract = ICoreNFTContract(assemble.issuerNFT);
        bytes32[] memory wallets = nftContract.getWallets(assemble.nftId);

        uint256[] memory chainList = nftContract.getChainList();
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

    function _verifyAllChainsReported(uint256 assembleId) internal view {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        ICoreNFTContract nftContract = ICoreNFTContract(assemble.issuerNFT);
        uint256[] memory chainList = nftContract.getChainList();
        for (uint256 i = 0; i < chainList.length; i++) {
            bytes32[] memory walletsWithPositiveLimit = nftContract.getWalletsWithLimitChain(assemble.nftId, chainList[i]);
            if (walletsWithPositiveLimit.length > 0) {
                require(assemble.chainReported[chainList[i]], "Not all chains have reported");
            }
        }
    }

    function liquidationChallenge(uint256 assembleId, bytes32 token, uint32 targetChainId, bytes32 recipientAddress, uint256[] memory gAssembleIds, bytes calldata _extraOptions) external payable {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        require(assemble.executor == msg.sender, "Not the present executor");
        ICoreNFTContract nftContract = ICoreNFTContract(assemble.issuerNFT);

        _verifyAllChainsReported(assembleId);

        uint256 lowestAssembleTimestamp;
        uint256 latestBorrowTimestamp;

        uint256 gNFTCount = nftContract.getGNFTCount(assemble.nftId);
        uint256 gTotalBorrowed;
        uint256 gTotalCollateral;
        if ( gNFTCount > 0) {
            uint256[] memory gNFTList = nftContract.getGNFTList(assemble.nftId);
            for (uint256 i = 0; i<gNFTList.length; i++){
                for (uint256 j = 0; j<gAssembleIds.length; j++){
                    AssemblePositions storage gAssemble = _assemblePositions[gAssembleIds[j]];
                    if (gNFTList[i] == gAssemble.nftId){
                        uint256 gAssembleId = currentIncompleteWithdrawalAssembleIds[gNFTList[i]];
                        require(gAssembleId != 0, "GAssemble doesnt exist");
                        (uint256 gBorrowed, uint256 gCollateral) = _calculateTotalPositions(gAssembleId);
                        gTotalBorrowed += gBorrowed;
                        gTotalCollateral += gCollateral;
                        lowestAssembleTimestamp = (lowestAssembleTimestamp == 0 || gAssemble.timestamp < lowestAssembleTimestamp) ? gAssemble.timestamp : lowestAssembleTimestamp;
                        latestBorrowTimestamp = gAssemble.latestBorrowTimestamp > latestBorrowTimestamp ? gAssemble.latestBorrowTimestamp : latestBorrowTimestamp;
                    }
                }
            }
            gTotalBorrowed += nftContract.getPWalletsTotalLimit(assemble.nftId);
        }

        // Calculate total borrow and deposit positions
        (uint256 totalBorrowed, uint256 totalCollateral) = _calculateTotalPositions(assembleId);

        // Calculate total available to withdraw
        uint256 liqThreshold = (totalCollateral * LIQ_THRESHOLD / 100) + nftContract.getExtraLimit(assemble.nftId); // TODO @attackvector can this be misused? the extra limit I mean
        
        require(totalBorrowed < liqThreshold, "Borrow position is above the liquidation threshold");

        lowestAssembleTimestamp = (lowestAssembleTimestamp == 0 || assemble.timestamp < lowestAssembleTimestamp) ? assemble.timestamp : lowestAssembleTimestamp;
        latestBorrowTimestamp = assemble.latestBorrowTimestamp > latestBorrowTimestamp ? assemble.latestBorrowTimestamp : latestBorrowTimestamp;

        // console2.log("Total borrowed: %s | Liq Threshold: %s", totalBorrowed, liqThreshold); // TODO remove after testing

        if (targetChainId == adminChainId) {
            IDepositContract depositContract = depositContracts[targetChainId];
            require(address(depositContract) != address(0), "Deposit contract not set for this chain");
            depositContract.onChainLiqChallenge(token, addressToBytes32(assemble.issuerNFT), assemble.nftId, lowestAssembleTimestamp, latestBorrowTimestamp, recipientAddress);
            challengeNonces[assemble.nftId]++;
        } else {
            _initiateCrossChainChallenge(token, assemble.issuerNFT, assemble.nftId, lowestAssembleTimestamp, latestBorrowTimestamp, recipientAddress, targetChainId, _extraOptions);
        }

        emit LiquidationChallenged(token, assemble.nftId, targetChainId, msg.sender);

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

    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function getWithdrawNonce(uint256 nftId) external view returns (uint256) {
        return withdrawalNonces[nftId];
    }

    function getAssembleChainsReported(uint256 assembleId) external view returns (uint256) {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        uint256 reportedChains = 0;

        uint256[] memory chainList = ICoreNFTContract(assemble.issuerNFT).getChainList();
        for (uint256 i = 0; i < chainList.length; i++) {
            if (assemble.chainReported[chainList[i]]) {
                reportedChains++;
            }
        }
        return reportedChains;
    }

    function setDepositContract(uint256 chainId, address contractAddress) external onlyOwner {
        require(address(depositContracts[chainId]) == address(0), "Deposit contract already set for this chain");
        depositContracts[chainId] = IDepositContract(contractAddress);
    }

    function setNewIssuer(address issuerNFT, address newIssuer) external onlyIssuer(issuerNFT) {
        issuers[issuerNFT] = newIssuer;
    }

    function hasIncompleteWithdrawalAssemble(uint256 nftId) public view returns (bool) {
        uint256 assembleId = currentIncompleteWithdrawalAssembleIds[nftId];
        return assembleId != 0 && !_assemblePositions[assembleId].isComplete;
    }

    function markAssembleComplete(uint256 assembleId) external {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        require(ICoreNFTContract(assemble.issuerNFT).isManagerOrOwner(assemble.nftId, msg.sender), "Not authorized");
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