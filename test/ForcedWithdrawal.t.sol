// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/src/Test.sol";
import "../src/SmokeDepositContract.sol";
import "../src/CoreNFTContract.sol";
import "../src/OperationsContract.sol";
import "../src/SmokeSpendingContract.sol";
import "../src/WstETHOracleReceiver.sol";

import "./Setup.t.sol";

import "../src/archive/weth.sol";
import "../src/archive/siggen.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {
    IOAppOptionsType3,
    EnforcedOptionParam
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";

contract DepositTest is Setup {
    using ECDSA for bytes32;
    using OptionsBuilder for bytes;

    uint16 SEND = 1;
    uint16 SEND_ABA = 2;

    function setUp() public override {
        super.setUp();
        super.setupRateLimits();
        // (issuer1, issuer1Pk) = makeAddrAndKey("issuer");
    }

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private constant BORROW_TYPEHASH = keccak256(
        "Borrow(address borrower,address issuerNFT,uint256 nftId,uint256 amount,uint256 timestamp,uint256 signatureValidity,uint256 nonce,address recipient)"
    );

    function neighborhoodBorrow(
        SmokeSpendingContract lendingContract,
        address userAddress,
        address issuerNFT,
        uint256 nftId,
        uint256 amount,
        uint256 timestamp,
        uint256 signatureValidityVar,
        uint256 nonce,
        bool wethBool,
        address recipient
    ) public {
        bytes memory signature = getIssuersSig(
            lendingContract, userAddress, issuerNFT, nftId, amount, timestamp, signatureValidityVar, nonce, recipient
        );

        lendingContract.borrow(
            issuerNFT, nftId, amount, timestamp, signatureValidityVar, nonce, recipient, wethBool, signature, 0
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
        uint256 nonce,
        address recipient
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
                BORROW_TYPEHASH, borrower, issuerNFT, nftId, amount, timestamp, signatureValidityVar, nonce, recipient
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuer1Pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function testForcedWithdrawal() public {
        uint256 signatureValidity = 2 minutes;

        // console.log("Issuer NFT ADdresss", issuer1NftAddress);

        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        vm.startPrank(user2);
        neighborhoodBorrow(
            lendingcontractB,
            user2,
            issuer1NftAddress,
            tokenId,
            uint256(0.5 * 10 ** 18),
            timestamp,
            signatureValidity,
            uint256(0),
            false,
            user2
        );
        vm.stopPrank();

        vm.warp(1720963281);
        timestamp = vm.getBlockTimestamp();

        vm.startPrank(user);
        neighborhoodBorrow(
            lendingcontractC,
            user,
            issuer1NftAddress,
            tokenId,
            uint256(0.1 * 10 ** 18),
            timestamp,
            signatureValidity,
            uint256(0),
            false,
            user2
        );
        vm.stopPrank();

        vm.warp(1720963381);
        console.log(
            "User's borrow pos on chain 3: ", lendingcontractC.getBorrowPosition(issuer1NftAddress, tokenId, user)
        );
        console.log(
            "User's borrow pos on chain 2: ", lendingcontractB.getBorrowPosition(issuer1NftAddress, tokenId, user2)
        );

        vm.prank(address(l2_messenger));
        wstETHOracle.setWstETHRatio(1.175 * 1e18);

        vm.startPrank(user);
        uint256 assembleId =
            assemblePositionsContract.createAssemblePositions(issuer1NftAddress, tokenId, true, address(user));
        vm.stopPrank();
        vm.startPrank(user);
        vm.expectRevert();
        assemblePositionsContract.createAssemblePositions(issuer1NftAddress, tokenId, true, address(user));
        vm.stopPrank();

        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0); // gas settings for B -> A

        bytes32[] memory walletsReqChain = issuer1NftContract.getWalletsWithLimitChain(tokenId, bEid);
        bytes memory payload = getReportPositionsPayload(assembleId, tokenId, walletsReqChain);

        // FIRST report
        MessagingFee memory sendFee = depositCrossB.quote(aEid, SEND, payload, extraOptions, false);

        vm.startPrank(user);
        // vm.expectEmit();
        // emit SmokeDepositContract.PositionsReported(assembleId, tokenId);

        vm.warp(1721063381);
        depositCrossB.reportPositions{value: sendFee.nativeFee}(
            assembleId, issuer1NftAddress, tokenId, walletsReqChain, extraOptions
        );
        vm.stopPrank();
        verifyPackets(aEid, addressToBytes32(address(accountOps)));

        // SECOND report
        sendFee = depositCrossC.quote(aEid, SEND, payload, extraOptions, false);

        vm.startPrank(user);
        depositCrossC.reportPositions{value: sendFee.nativeFee}(
            assembleId, issuer1NftAddress, tokenId, walletsReqChain, extraOptions
        );
        vm.stopPrank();
        verifyPackets(aEid, addressToBytes32(address(accountOps)));

        // THIRD report
        walletsReqChain = issuer1NftContract.getWalletsWithLimitChain(tokenId, dEid);
        payload = getReportPositionsPayload(assembleId, tokenId, walletsReqChain);
        sendFee = depositCrossD.quote(aEid, SEND, payload, extraOptions, false);

        vm.startPrank(user);
        depositCrossD.reportPositions{value: sendFee.nativeFee}(
            assembleId, issuer1NftAddress, tokenId, walletsReqChain, extraOptions
        );
        vm.stopPrank();
        verifyPackets(aEid, addressToBytes32(address(accountOps)));

        // Fourth report
        walletsReqChain = issuer1NftContract.getWalletsWithLimitChain(tokenId, aEid);
        accountOps.getOnChainReport(assembleId, issuer1NftAddress, tokenId, walletsReqChain, new bytes(0));
        payload = getReportPositionsPayload(assembleId, tokenId, walletsReqChain);

        assertEq(assemblePositionsContract.getReportedAssembleChains(assembleId), 4);

        uint256[] memory withdrawAmounts = new uint256[](2);
        uint32[] memory targetChainIds = new uint32[](2);
        withdrawAmounts[0] = 0.9 * 1e18;
        withdrawAmounts[1] = 0.69 * 1e18;
        targetChainIds[0] = aEid;
        targetChainIds[1] = bEid;

        extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250000, 0); // gas settings for B -> A

        payload =
            abi.encode(address(user), address(weth), tokenId, 0.9 * 10 ** 18, accountOps.withdrawalNonces(tokenId));

        sendFee = accountOps.quote(bEid, SEND, accountOps.encodeMessage(1, payload), extraOptions, false);

        console.log(assemblePositionsContract.getAssembleBorrowPosition(assembleId, 2, addressToBytes32(user)));
        vm.startPrank(user);
        accountOps.forcedWithdrawal{value: sendFee.nativeFee}(
            assembleId,
            addressToBytes32(address(weth)),
            withdrawAmounts,
            targetChainIds,
            addressToBytes32(address(user)),
            extraOptions
        );
        vm.stopPrank();
        verifyPackets(bEid, addressToBytes32(address(depositCrossB)));

        assertEq(depositCrossB.getDepositAmount(issuer1NftAddress, tokenId, address(weth)), 0.31 * 1e18);

        withdrawAmounts = new uint256[](1);
        targetChainIds = new uint32[](1);
        withdrawAmounts[0] = 0.7 * 1e18;
        targetChainIds[0] = dEid;

        vm.startPrank(user);
        assemblePositionsContract.markAssembleComplete(assembleId);
        vm.stopPrank();
        extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(90000, 0); // gas settings for B -> A

        payload = abi.encode(address(user), address(weth), tokenId, 1 * 10 ** 18, accountOps.withdrawalNonces(tokenId));

        sendFee = accountOps.quote(dEid, SEND, payload, extraOptions, false);
        vm.startPrank(user);
        vm.expectRevert();
        accountOps.forcedWithdrawal{value: sendFee.nativeFee}(
            assembleId,
            addressToBytes32(address(wstETH)),
            withdrawAmounts,
            targetChainIds,
            addressToBytes32(address(user)),
            extraOptions
        );
        vm.stopPrank();
        verifyPackets(dEid, addressToBytes32(address(depositCrossD)));

        // assertEq(depositCrossD.getDepositAmount(address(wstETH), tokenId), 0.3 * 10**18);
        vm.prank(issuer1);
    }

    function getReportPositionsPayload(uint256 tokenId2, uint256 assembleId, bytes32[] memory walletsReqChain)
        private
        pure
        returns (bytes memory payload)
    {
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
}
