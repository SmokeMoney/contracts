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


    function setUp() public virtual override {
        super.setUp();

        (issuer1, issuer1Pk) = makeAddrAndKey("issuer1");

        uint256 signatureValidity = 2 minutes;

        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        bytes32 digest = keccak256(abi.encodePacked(user2, tokenId, uint256(2.8 * 10**18), timestamp, uint256(0), uint256(bEid)));
        bytes memory signature = getIssuersSig(digest); // note the order here is different from line above.

        vm.startPrank(user2);
        lendingcontractB.borrow(issuer1NftAddress, tokenId, uint256(2.8 * 10**18), timestamp, signatureValidity, uint256(0), false, signature);
        vm.stopPrank();

        vm.warp(1720963281);
        timestamp = vm.getBlockTimestamp();
        digest = keccak256(abi.encodePacked(user, tokenId, uint256(0.19 * 10**18), timestamp, uint256(0), uint256(cEid)));
        signature = getIssuersSig(digest); 

        vm.startPrank(user);
        lendingcontractC.borrow(issuer1NftAddress, tokenId, uint256(0.19 * 10**18), timestamp, signatureValidity, uint256(0), false, signature);
        
        vm.stopPrank();


        vm.warp(1720963381);
        console.log("User's borrow pos on chain 3: ", lendingcontractC.getBorrowPosition(issuer1NftAddress, tokenId, user));
        console.log("User's borrow pos on chain 2: ", lendingcontractB.getBorrowPosition(issuer1NftAddress, tokenId, user2));
        
    }

    function testOptimisticLiquidation() public {

        vm.warp(1720962281);
        vm.startPrank(issuer1);
        weth.deposit{value:0.1 * 1e18}();
        weth.approve(address(depositCrossB), 0.1 * 1e18);
        depositCrossB.lockForLiquidation(address(weth), issuer1NftAddress, tokenId, 1e18);
        vm.warp(1721073281);
        depositCrossB.executeLiquidation(address(weth), issuer1NftAddress, tokenId, 1e18);
        vm.stopPrank();
        
    }

    function testLiquidationChallenge() public {

        vm.warp(1724984381);
        vm.startPrank(issuer1);
        weth.deposit{value:1 * 1e18}();
        weth.approve(address(depositCrossB), 0.1 * 1e18);
        weth.approve(address(depositLocal), 0.1 * 1e18);
        depositCrossB.lockForLiquidation(address(weth), issuer1NftAddress, tokenId, 1e18);
        depositLocal.lockForLiquidation(address(weth), issuer1NftAddress, tokenId, 1e18);
        vm.stopPrank();

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
        console.logBytes(new bytes(0));
        console.logBytes(payload);
        console.logBytes(extraOptions);

        // FIRST report
        MessagingFee memory sendFee = depositCrossB.quote(aEid, SEND, payload, extraOptions, false);

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
        
        assertEq(accountOps.getAssembleChainsReported(assembleId), 4);

        console.log(weth.balanceOf(issuer1));
        vm.startPrank(userB);
        uint256[] memory gAssembleIds = new uint256[](0);
        accountOps.liquidationChallenge(assembleId, addressToBytes32(address(weth)), aEid, addressToBytes32(address(userB)), gAssembleIds, new bytes(0));


        extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(70000, 0); // gas settings for B -> A

        payload = abi.encode(
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
        console.log(weth.balanceOf(issuer1));

        assertEq(depositLocal.isLiquidationLocked(address(weth), issuer1NftAddress, tokenId), false);
        assertEq(depositCrossB.isLiquidationLocked(address(weth), issuer1NftAddress, tokenId), false);

    }

    function getIssuersSig(bytes32 digest) private view returns (bytes memory signature) {
        bytes32 hash = siggen.getEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuer1Pk, hash);
        signature = abi.encodePacked(r, s, v);
    }

    function getReportPositionsPayload(uint256 tokenId2, uint256 assembleId, bytes32[] memory walletsReqChain) private pure returns ( bytes memory payload ){
        uint256 depositAmount = 0;
        uint256 wstETHDepositAmount = 0;
        address wethAddress = address(0);
        address wstETHAddress = address(0);
        uint256[] memory borrowAmounts = new uint256[](walletsReqChain.length);
        uint256[] memory interestAmounts = new uint256[](walletsReqChain.length);

        payload = abi.encode(
            assembleId, 
            tokenId2, 
            depositAmount, 
            wstETHDepositAmount, 
            wethAddress, 
            wstETHAddress,
            depositAmount,
            walletsReqChain,
            borrowAmounts,
            interestAmounts
        );
    }


}