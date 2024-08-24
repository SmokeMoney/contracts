// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./Setup.t.sol";
import "../src/deposit.sol";
import "../src/corenft.sol";
import "../src/accountops.sol";
import "../src/borrow.sol";
import "../src/archive/weth.sol";
import "../src/archive/siggen.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";


contract DepositTest is Setup {
    using ECDSA for bytes32;
    using OptionsBuilder for bytes;

    uint16 SEND = 1;
    uint16 SEND_ABA = 2;

    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 public constant BORROW_TYPEHASH = keccak256(
        "Borrow(address borrower,address issuerNFT,uint256 nftId,uint256 amount,uint256 timestamp,uint256 signatureValidity,uint256 nonce,bool weth)"
    );


    function setUp() public virtual override {
        super.setUp();
        super.setupRateLimits();

        uint256 signatureValidity = 2 minutes;
        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        vm.startPrank(user2);
        neighborhoodBorrow(lendingcontractB, user2, issuer1NftAddress, tokenId, uint256(2.8 * 10**18), timestamp, signatureValidity, uint256(0), false);
        vm.stopPrank();

        vm.warp(1720963281);
        timestamp = vm.getBlockTimestamp();
        
        vm.startPrank(user);
        neighborhoodBorrow(lendingcontractC, user, issuer1NftAddress, tokenId, uint256(0.19 * 10**18), timestamp, signatureValidity, uint256(0), false);
        vm.stopPrank();

        vm.warp(1720963381);
        // console.log("User's borrow pos on chain 3: ", lendingcontractC.getBorrowPosition(issuer1NftAddress, tokenId, user));
        // console.log("User's borrow pos on chain 2: ", lendingcontractB.getBorrowPosition(issuer1NftAddress, tokenId, user2));
    }

    function testOptimisticLiquidation() public {

        vm.warp(1720962281);
        vm.startPrank(issuer1);
        weth.deposit{value:0.1 * 1e18}();
        weth.approve(address(depositCrossB), 0.1 * 1e18);
        depositCrossB.lockForLiquidation(issuer1NftAddress, tokenId, address(weth));
        vm.warp(1721073281);
        depositCrossB.executeLiquidation(issuer1NftAddress, tokenId, address(weth));
        vm.stopPrank();
        
    }

    function testLiquidationChallenge() public {

        vm.warp(1724984381);
        vm.startPrank(issuer1);
        weth.deposit{value:1 * 1e18}();
        weth.approve(address(depositCrossB), 1 * 1e18);
        weth.approve(address(depositLocal), 2 * 1e18);
        depositCrossB.lockForLiquidation(issuer1NftAddress, tokenId, address(weth));
        depositLocal.lockForLiquidation(issuer1NftAddress, tokenId, address(weth));
        vm.stopPrank();

        console.log("Deposits on chain A (WETH)", depositLocal.getDepositAmount(issuer1NftAddress, tokenId, address(weth)) * 1000 / 1e18);
        console.log("Deposits on chain B (WETH)", depositCrossB.getDepositAmount(issuer1NftAddress, tokenId, address(weth)) * 1000 / 1e18);
        console.log("Challenger Balance: ", userB.balance * 1000 / 1e18);
        console.log("Challenger Balance: ", weth.balanceOf(userB) * 1000 / 1e18);
        console.log("Issuer Balance: ", issuer1.balance * 1000 / 1e18);
        console.log("Issuer Balance: ", weth.balanceOf(issuer1) * 1000 / 1e18);

        vm.prank(address(l2_messenger));
        wstETHOracle.setWstETHRatio(1.175*1e18);

        vm.warp(1724985381);
        vm.startPrank(userB);
        uint256 assembleId = accountOps.createAssemblePositions(issuer1NftAddress, tokenId, false, address(userB));
        vm.stopPrank();

        vm.startPrank(user);
        lendingcontractB.repay{value: 1e18}(issuer1NftAddress, tokenId, address(user2), address(user));
        vm.stopPrank();

        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0); // gas settings for B -> A


        bytes32[] memory walletsReqChain = issuer1NftContract.getWalletsWithLimitChain(tokenId, bEid);
        bytes memory payload = getReportPositionsPayload(assembleId, tokenId, walletsReqChain);
        // console.logBytes(payload);
        // console.logBytes(extraOptions);

        // FIRST report
        MessagingFee memory sendFee = depositCrossB.quote(aEid, SEND, payload, extraOptions, false);

        vm.startPrank(userB);
        weth.deposit{value:0.3*1e18}();
        weth.approve(address(depositLocal), 0.2 * 1e18);
        weth.approve(address(depositCrossB), 0.1 * 1e18);

        depositLocal.quickChallenge(issuer1NftAddress, tokenId, address(weth));
        depositCrossB.quickChallenge(issuer1NftAddress, tokenId, address(weth));
        vm.stopPrank();

        vm.warp(1725073002);
        vm.startPrank(user);
        vm.expectEmit();
        emit AdminDepositContract.PositionsReported(assembleId, issuer1NftAddress, tokenId);

        depositCrossB.reportPositions{value: sendFee.nativeFee}(assembleId, issuer1NftAddress, tokenId, walletsReqChain, extraOptions);
        vm.stopPrank();
        verifyPackets(aEid, addressToBytes32(address(accountOps)));

        // SECOND report
        sendFee = depositCrossC.quote(aEid, SEND, payload, extraOptions, false);

        vm.startPrank(user);
        depositCrossC.reportPositions{value: sendFee.nativeFee}(assembleId, issuer1NftAddress, tokenId, walletsReqChain, extraOptions);
        vm.stopPrank();
        verifyPackets(aEid, addressToBytes32(address(accountOps)));

        // THIRD report
        walletsReqChain = issuer1NftContract.getWalletsWithLimitChain(tokenId, dEid);
        payload = getReportPositionsPayload(assembleId, tokenId, walletsReqChain);
        sendFee = depositCrossD.quote(aEid, SEND, payload, extraOptions, false);

        vm.startPrank(user);
        depositCrossD.reportPositions{value: sendFee.nativeFee}(assembleId, issuer1NftAddress, tokenId, walletsReqChain, extraOptions);
        vm.stopPrank();
        verifyPackets(aEid, addressToBytes32(address(accountOps)));
        

        // Fourth report
        walletsReqChain = issuer1NftContract.getWalletsWithLimitChain(tokenId, aEid);
        accountOps.getOnChainReport(assembleId, issuer1NftAddress, tokenId, walletsReqChain, new bytes(0));
        payload = getReportPositionsPayload(assembleId, tokenId, walletsReqChain);
        
        assertEq(accountOps.getReportedAssembleChains(assembleId), 4);

        vm.startPrank(userB);
        uint256[] memory gAssembleIds = new uint256[](0);
        accountOps.liquidationChallenge(assembleId, addressToBytes32(address(weth)), aEid, addressToBytes32(address(userB)), gAssembleIds, new bytes(0));

        console.log("Challenger Balance after 1: ", userB.balance * 1000 / 1e18);
        console.log("Challenger Balance after 1: ", weth.balanceOf(userB) * 1000 / 1e18);
        console.log("Issuer Balance after 1: ", issuer1.balance * 1000 / 1e18);
        console.log("Issuer Balance after 1: ", weth.balanceOf(issuer1) * 1000 / 1e18);

        extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(70000, 0); // gas settings for B -> A

        payload = abi.encode(
            address(0),
            address(0),
            address(0),
            tokenId,
            assembleId, // random uint256, just for calculations
            assembleId, // random uint256, just for calculations
            assembleId
        );

        sendFee = accountOps.quote(bEid, SEND, accountOps.encodeMessage(2, payload), extraOptions, false);

        accountOps.liquidationChallenge{value: sendFee.nativeFee}(assembleId, addressToBytes32(address(weth)), bEid, addressToBytes32(address(userB)), gAssembleIds, extraOptions);

        verifyPackets(bEid, addressToBytes32(address(depositCrossB)));
        vm.stopPrank();

        console.log("Challenger Balance after 2: ", userB.balance * 1000 / 1e18);
        console.log("Challenger Balance after 2: ", weth.balanceOf(userB) * 1000 / 1e18);
        console.log("Issuer Balance after 2: ", issuer1.balance * 1000 / 1e18);
        console.log("Issuer Balance after 2: ", weth.balanceOf(issuer1) * 1000 / 1e18);
        assertEq(depositLocal.isLiquidationLocked(issuer1NftAddress, tokenId, address(weth)), false);
        assertEq(depositCrossB.isLiquidationLocked(issuer1NftAddress, tokenId, address(weth)), false);
    }

    function getReportPositionsPayload(uint256 tokenId2, uint256 assembleId, bytes32[] memory walletsReqChain) private pure  returns ( bytes memory payload ){
        uint256 depositAmount = 0;
        uint256 wstETHDepositAmount = 0;
        uint256[] memory borrowAmounts = new uint256[](walletsReqChain.length);
        uint256[] memory interestAmounts = new uint256[](walletsReqChain.length);

        payload = abi.encode(
            assembleId, 
            addressToBytes32(address(69)), // issuer nft address
            tokenId2, 
            depositAmount, 
            wstETHDepositAmount,
            addressToBytes32(address(0)), // wstETHaddress
            depositAmount, // random uint256 for testing
            depositAmount, // random uint256 for testing
            walletsReqChain,
            borrowAmounts,
            interestAmounts
        );
    }
    function neighborhoodBorrow(
        SmokeSpendingContract lendingContract,
        address userAddress,
        address issuerNFT,
        uint256 nftId,
        uint256 amount,
        uint256 timestamp,
        uint256 signatureValidityVar,
        uint256 nonce,
        bool wethBool
    ) public {
        bytes memory signature = getIssuersSig(
            lendingContract,
            userAddress,
            issuerNFT,
            nftId,
            amount,
            timestamp,
            signatureValidityVar,
            nonce
        );

        lendingContract.borrow(
            issuerNFT,
            nftId,
            amount,
            timestamp,
            signatureValidityVar,
            nonce,
            wethBool,
            signature
        );
    }

    function getIssuersSig(
        SmokeSpendingContract lendingContract,
        address borrower,
        address issuerNFT,
        uint256 nftId,
        uint256 amount,
        uint256 timestamp,
        uint256 signatureValidityVar,
        uint256 nonce
    ) private view returns (bytes memory) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("SmokeSpendingContract")),
                keccak256(bytes("1")),
                31337,
                address(lendingContract)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                BORROW_TYPEHASH,
                borrower,
                issuerNFT,
                nftId,
                amount,
                timestamp,
                signatureValidityVar,
                nonce
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuer1Pk, digest);
        return abi.encodePacked(r, s, v);
    }


}