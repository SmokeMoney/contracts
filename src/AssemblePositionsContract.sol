// SPDX-License-Identifier: CTOSL
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/ICoreNFTContract.sol";
import "./interfaces/IWstETHOracleReceiver.sol";
import "./interfaces/IDepositContract.sol";

import { console2 } from "forge-std/Test.sol"; // TODO REMOVE AFDTRER TEST
contract AssemblePositionsContract {
    using ECDSA for bytes32;

    struct AssemblePositions {
        address issuerNFT;
        uint256 nftId;
        mapping(uint256 => bool) chainReported;
        mapping(uint256 => mapping(bytes32 => uint256)) borrowPositions; // chainID -> wallet -> position
        mapping(uint256 => uint256) depositPositions;
        mapping(uint256 => uint256) wstETHDepositPositions;
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
        bytes32 wstETHAddress;
        uint256 reportPositionTimestamp;
    }
    
    struct WalletData {
        bytes32[] wallets;
        uint256[] borrowAmounts;
        uint256[] interestAmounts;
        uint256 latestBorrowTimestamp;
    }

    mapping(uint256 => AssemblePositions) private _assemblePositions;
    mapping(uint256 => uint256) public currentIncompleteWithdrawalAssembleIds;
    uint256 private _currentAssembleId;

    IWstETHOracleReceiver public wstETHOracle;

    address public operationsContract;

    event AssemblePositionsCreated(uint256 indexed assembleId, uint256 indexed nftId, bool forWithdrawal);
    event ChainPositionReported(uint256 indexed assembleId, uint256 chainId);

    constructor(address _wstETHOracleContract) {
        wstETHOracle = IWstETHOracleReceiver(_wstETHOracleContract);
        _currentAssembleId = 1;
    }

    modifier onlyOperationsContract() {
        require(msg.sender == operationsContract, "Caller is not the OperationsContract");
        _;
    }

    function setOperationsContract(address _operationsContract) external {
        require(operationsContract == address(0), "Ops contract already set");
        operationsContract = _operationsContract;
    }

    function createAssemblePositions(
        address issuerNFT,
        uint256 nftId,
        bool forWithdrawal,
        address executor
    ) external returns (uint256) {
        // require(issuers[issuerNFT] != address(0), "Invalid issuer"); // @attackVector if I create an assemble for empty issuers, is that exploitable? 
        require(forWithdrawal == false || ICoreNFTContract(issuerNFT).ownerOf(nftId) == msg.sender || nftId > ICoreNFTContract(issuerNFT).getTotalSupply(), "Not manager or owner for withdrawal");
        
        if (forWithdrawal) {
            uint256 currentIncompleteAssembleId = currentIncompleteWithdrawalAssembleIds[nftId];
            require(currentIncompleteAssembleId == 0 || _assemblePositions[currentIncompleteAssembleId].isComplete, 
                    "An incomplete withdrawal assemble already exists for this NFT");
        }

        uint256 assembleId = _currentAssembleId++;
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
        require(block.timestamp - lastUpdateTimestamp < 12 hours, 'Last oracle update is too old, please refresh');

        emit AssemblePositionsCreated(assembleId, nftId, forWithdrawal);

        return assembleId;
    }

    function setupAssemble(uint32 srcChainId, bytes memory _payload) external onlyOperationsContract returns (uint256) {
        (AssembleData memory assembleData, WalletData memory walletData) = _decodeAssemblePayload(_payload);
    
        AssemblePositions storage assemble = _assemblePositions[assembleData.assembleId];

        require(assemble.issuerNFT == assembleData.issuerNFT, "Invalid Issuer ID");
        require(assemble.nftId == assembleData.nftId, "Invalid NFT ID");
        require(!assemble.chainReported[srcChainId], "Chain already reported");
        require(assemble.timestamp + 20 minutes < assembleData.reportPositionTimestamp, "Reported too soon");
    
        assemble.chainReported[srcChainId] = true;
        assemble.depositPositions[srcChainId] = assembleData.depositAmount;
        assemble.wstETHDepositPositions[srcChainId] = assembleData.wstETHDepositAmount;
        assemble.wstETHAddresses[srcChainId] = assembleData.wstETHAddress;
        assemble.latestBorrowTimestamp = assemble.latestBorrowTimestamp > walletData.latestBorrowTimestamp 
            ? assemble.latestBorrowTimestamp 
            : walletData.latestBorrowTimestamp;

        _setupWalletPositions(assemble, assembleData, walletData, srcChainId);
        emit ChainPositionReported(assembleData.assembleId, srcChainId);

        return assembleData.assembleId;
    }

    function _setupWalletPositions(
        AssemblePositions storage assemble,
        AssembleData memory assembleData,
        WalletData memory walletData,
        uint256 srcChainId
    ) private {

        ICoreNFTContract nftContract = ICoreNFTContract(assemble.issuerNFT);

        if (assemble.nftId > nftContract.getTotalSupply()) { // gNFTs are always above the total Supply
            bytes32 gWallet = nftContract.getGWallet(assemble.nftId);
            require(isAddressInArray(walletData.wallets, gWallet), "GWallet does not exist");
        } else {
            bytes32[] memory walletsReqChain = nftContract.getWalletsWithLimitChain(assembleData.nftId, srcChainId);
            // console2.log("walletsReqChain length: %s | borrow amount: %s | approved limit: %s", walletsReqChain.length, 3, 2); // TODO remove after testing

            require(walletData.wallets.length == walletsReqChain.length, "Wallet list length mismatch");
            for (uint256 i = 0; i < walletsReqChain.length; i++) {
                require(isAddressInArray(walletData.wallets, walletsReqChain[i]), "Wallet lists do not match");
            }
        }
    
        for (uint256 i = 0; i < walletData.wallets.length; i++) {

            uint256 approvedLimit = nftContract.getWalletChainLimit(assembleData.nftId, walletData.wallets[i], srcChainId);
            // console2.log("srcChainId: %s | borrow amount: %s | approved limit: %s", srcChainId, walletData.borrowAmounts[i], approvedLimit); // TODO remove after testing

            uint256 validBorrowAmount = walletData.borrowAmounts[i] > approvedLimit 
                ? approvedLimit + walletData.interestAmounts[i] 
                : walletData.borrowAmounts[i] + walletData.interestAmounts[i];
            assemble.borrowPositions[srcChainId][walletData.wallets[i]] = validBorrowAmount;
        }
    }

    function _decodeAssemblePayload(bytes memory _payload) private pure returns (AssembleData memory, WalletData memory) {
        (
            uint256 assembleId,
            bytes32 issuerNFT,
            uint256 nftId,
            uint256 depositAmount,
            uint256 wstETHDepositAmount,
            bytes32 wstETHAddress,
            uint256 latestBorrowTimestamp,
            uint256 reportPositionTimestamp,
            bytes32[] memory wallets,
            uint256[] memory borrowAmounts,
            uint256[] memory interestAmounts
        ) = abi.decode(_payload, (uint256, bytes32, uint256, uint256, uint256, bytes32, uint256, uint256, bytes32[], uint256[], uint256[]));
    
        return (
            AssembleData(assembleId, bytes32ToAddress(issuerNFT), nftId, depositAmount, wstETHDepositAmount, wstETHAddress, reportPositionTimestamp),
            WalletData(wallets, borrowAmounts, interestAmounts, latestBorrowTimestamp)
        );
    }

    function isAddressInArray(bytes32[] memory array, bytes32 target) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == target) {
                return true;
            }
        }
        return false;
    }

    function verifyAllChainsReported(uint256 assembleId) external view {
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

    function calculateTotatPositionsWithdrawal(uint256 assembleId, uint256 nftId) external view returns (uint256 totalBorrowed, uint256 totalCollateral) {
        ICoreNFTContract nftContract = ICoreNFTContract(_assemblePositions[nftId].issuerNFT);

        uint256 gTotalBorrowed; 
        uint256 gTotalCollateral;
        // Calculate total borrow and deposit positions

        uint256 gNFTCount = nftContract.getGNFTCount(nftId);

        if ( gNFTCount > 0) {
            uint256[] memory gNFTList = nftContract.getGNFTList(nftId);
            for (uint256 i = 0; i<gNFTList.length; i++){
                uint256 gAssembleId = currentIncompleteWithdrawalAssembleIds[gNFTList[i]];
                require(gAssembleId != 0, "GAssemble doesnt exist");
                (uint256 gBorrowed, uint256 gCollateral) = _calculateTotalPositions(gAssembleId);
                gTotalBorrowed += gBorrowed;
                gTotalCollateral += gCollateral;
            }
            gTotalBorrowed += nftContract.getPWalletsTotalLimit(nftId);
        }

        (totalBorrowed, totalCollateral) = _calculateTotalPositions(assembleId);
        totalBorrowed += gTotalBorrowed;
        totalCollateral += gTotalCollateral;
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
                totalBorrowed += assemble.borrowPositions[chainList[j]][wallets[i]];            
            }
        }
    }

    function calculateTimestamps(uint256 assembleId, uint256[] memory gAssembleIds) external view returns (uint256 lowestAssembleTimestamp, uint256 latestBorrowTimestamp) {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        ICoreNFTContract nftContract = ICoreNFTContract(assemble.issuerNFT);

        lowestAssembleTimestamp = assemble.timestamp;
        latestBorrowTimestamp = assemble.latestBorrowTimestamp;

        uint256[] memory gNFTList = nftContract.getGNFTList(assemble.nftId);
        for (uint256 i = 0; i < gNFTList.length; i++) {
            for (uint256 j = 0; j < gAssembleIds.length; j++) {
                AssemblePositions storage gAssemble = _assemblePositions[gAssembleIds[j]];
                if (gNFTList[i] == gAssemble.nftId) {
                    lowestAssembleTimestamp = gAssemble.timestamp < lowestAssembleTimestamp ? gAssemble.timestamp : lowestAssembleTimestamp;
                    latestBorrowTimestamp = gAssemble.latestBorrowTimestamp > latestBorrowTimestamp ? gAssemble.latestBorrowTimestamp : latestBorrowTimestamp;
                }
            }
        }
    }

    function verifyLiquidationThreshold(uint256 assembleId, uint256[] memory gAssembleIds) external view {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        ICoreNFTContract nftContract = ICoreNFTContract(assemble.issuerNFT);

        (uint256 totalBorrowed, uint256 totalCollateral) = _calculateTotalPositionsWithGNFTs(assembleId, gAssembleIds);

        uint256 liqThreshold = (totalCollateral * nftContract.getLiquidationThreshold() / 10000) + nftContract.getNativeCredit(assemble.nftId);
        require(totalBorrowed < liqThreshold, "Borrow position is below the liquidation threshold");
    }

    function _calculateTotalPositionsWithGNFTs(uint256 assembleId, uint256[] memory gAssembleIds) internal view returns (uint256 totalBorrowed, uint256 totalCollateral) {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        ICoreNFTContract nftContract = ICoreNFTContract(assemble.issuerNFT);
        
        (totalBorrowed, totalCollateral) = _calculateTotalPositions(assembleId);
        
        uint256 gNFTCount = nftContract.getGNFTCount(assemble.nftId);
        if (gNFTCount > 0) {
            uint256[] memory gNFTList = nftContract.getGNFTList(assemble.nftId);
            for (uint256 i = 0; i<gNFTList.length; i++){
                for (uint256 j = 0; j<gAssembleIds.length; j++){
                    AssemblePositions storage gAssemble = _assemblePositions[gAssembleIds[j]];
                    if (gNFTList[i] == gAssemble.nftId){
                        require(gAssembleIds[j] != 0, "GAssemble doesnt exist");
                        (uint256 gBorrowed, uint256 gCollateral) = _calculateTotalPositions(gAssembleIds[j]);
                        totalBorrowed += gBorrowed;
                        totalCollateral += gCollateral;
                    }
                }
            }
            totalBorrowed += nftContract.getPWalletsTotalLimit(assemble.nftId);
        }
    }

    function setTotalAvailableToWithdraw(uint256 assembleId, uint256 _totalAvailableToWithdraw) external onlyOperationsContract {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        assemble.totalAvailableToWithdraw = _totalAvailableToWithdraw;
    }

    function getAssemblePositionsBasic(uint256 assembleId) external view returns (
        address issuerNFT,
        uint256 nftId,
        bool isComplete,
        bool forWithdrawal,
        uint256 timestamp,
        uint256 wstETHRatio,
        address executor,
        uint256 totalAvailableToWithdraw,
        uint256 latestBorrowTimestamp
    ) {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        return (
            assemble.issuerNFT,
            assemble.nftId,
            assemble.isComplete,
            assemble.forWithdrawal,
            assemble.timestamp,
            assemble.wstETHRatio,
            assemble.executor,
            assemble.totalAvailableToWithdraw,
            assemble.latestBorrowTimestamp
        );
    }

    function getAssembleBorrowPosition(uint256 assembleId, uint256 chainId, bytes32 wallet) external view returns (uint256) {
        return _assemblePositions[assembleId].borrowPositions[chainId][wallet];
    }

    function getAssembleWstETHAddresses(uint256 assembleId, uint256 chainId) external view returns (bytes32) {
        return _assemblePositions[assembleId].wstETHAddresses[chainId];
    }

    function getAssembleDepositPosition(uint256 assembleId, uint256 chainId) external view returns (uint256, uint256) {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        return (assemble.depositPositions[chainId], assemble.wstETHDepositPositions[chainId]);
    }

    function hasIncompleteWithdrawalAssemble(uint256 nftId) public view returns (bool) {
        uint256 assembleId = currentIncompleteWithdrawalAssembleIds[nftId];
        return assembleId != 0 && !_assemblePositions[assembleId].isComplete;
    }

    function markAssembleComplete(uint256 assembleId) external {

        AssemblePositions storage assemble = _assemblePositions[assembleId];
        require(ICoreNFTContract(assemble.issuerNFT).ownerOf(assemble.nftId) == msg.sender || operationsContract == msg.sender, "Not authorized");
        assemble.isComplete = true;

        if (assemble.forWithdrawal && assembleId == currentIncompleteWithdrawalAssembleIds[assemble.nftId]) {
            currentIncompleteWithdrawalAssembleIds[assemble.nftId] = 0;
        }
    }

    function getReportedAssembleChains(uint256 assembleId) external view returns (uint256) {
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

    function bytes32ToAddress(bytes32 _bytes) internal pure returns (address) {
        return address(uint160(uint256(_bytes)));
    }

    // Additional helper functions as needed...
}