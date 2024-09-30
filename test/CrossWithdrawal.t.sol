// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/src/Test.sol";
import "../src/SmokeDepositContract.sol";
import "../src/CoreNFTContract.sol";
import "../src/OperationsContract.sol";
import "../src/archive/weth.sol";
import "../src/archive/siggen.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import "./Setup.t.sol";

contract DepositTest is Setup {
    using ECDSA for bytes32;
    using OptionsBuilder for bytes;

    uint16 SEND = 1;

    function setUp() public virtual override {
        super.setUp();
    }

    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 private constant WITHDRAW_TYPEHASH = keccak256(
        "Withdraw(address issuerNFT,bytes32 token,uint256 nftId,uint256 amount,uint32 targetChainId,uint256 timestamp,uint256 nonce,bool primary,bytes32 recipientAddress)"
    );

    // Add more test cases here, for example:
    function testWithdrawOnChain() public {

        uint timestamp = vm.unixTime();

        bytes memory options = new bytes(0);

        OperationsContract.WithdrawParams memory params = OperationsContract.WithdrawParams({
            issuerNFT: issuer1NftAddress,
            token: addressToBytes32(address(weth)),
            nftId: tokenId,
            amount: 0.1 * 10**18,
            targetChainId: aEid,
            timestamp: timestamp,
            nonce: 0,
            primary: true,
            recipientAddress: addressToBytes32(address(user))
        });

        bytes memory signature = getIssuersSig(accountOps, params); // note the order here is different from line above.

        vm.startPrank(user);
        accountOps.withdraw(params, signature, options);
        vm.stopPrank();
        assertEq(depositLocal.getDepositAmount(issuer1NftAddress, tokenId, address(weth)), 1.9 * 10**18);
    }

            // Add more test cases here, for example:
    function testWithdrawCrossChain() public {

        EnforcedOptionParam[] memory aEnforcedOptions = new EnforcedOptionParam[](1);
        // Send gas for lzReceive (A -> B).
        aEnforcedOptions[0] = EnforcedOptionParam({eid: bEid, msgType: SEND, options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(90000, 0)}); // gas limit, msg.value
        // Send gas for lzReceive + msg.value for nested lzSend (A -> B -> A).        
        
        vm.startPrank(address(this));
        accountOps.setEnforcedOptions(aEnforcedOptions);
        vm.stopPrank();

        uint timestamp = vm.unixTime();

        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(90000, 0); // gas settings for B -> A

        bytes memory payload = abi.encode(
            address(user),
            address(weth),
            tokenId,
            0.1 * 10**18,
            accountOps.withdrawalNonces(tokenId)
        );

        MessagingFee memory sendFee = accountOps.quote(bEid, SEND, accountOps.encodeMessage(1, payload), extraOptions, false);

        OperationsContract.WithdrawParams memory params = OperationsContract.WithdrawParams({
            issuerNFT: issuer1NftAddress,
            token: addressToBytes32(address(weth)),
            nftId: tokenId,
            amount: 0.1 * 10**18,
            targetChainId: bEid,
            timestamp: timestamp,
            nonce: 0,
            primary: true,
            recipientAddress: addressToBytes32(address(user))
        });

        bytes memory signature = getIssuersSig(accountOps, params);  // note the order here is different from line above.

        vm.startPrank(user);
        accountOps.withdraw{value: sendFee.nativeFee}(params, signature, extraOptions);
        vm.stopPrank();
        verifyPackets(bEid, addressToBytes32(address(depositCrossB)));

        assertEq(depositCrossB.getDepositAmount(issuer1NftAddress, tokenId, address(weth)), 0.9 * 10**18);

        timestamp = vm.unixTime();

        payload = abi.encode(
            address(user),
            address(weth),
            tokenId,
            0.1 * 10**18,
            accountOps.withdrawalNonces(tokenId)
        );

        sendFee = accountOps.quote(bEid, SEND, accountOps.encodeMessage(1, payload), extraOptions, false);

        params = OperationsContract.WithdrawParams({
            issuerNFT: issuer1NftAddress,
            token: addressToBytes32(address(weth)),
            nftId: tokenId,
            amount: 0.1 * 10**18,
            targetChainId: bEid,
            timestamp: timestamp,
            nonce: 1,
            primary: true,
            recipientAddress: addressToBytes32(address(user))
        });

        signature = getIssuersSig(accountOps, params);  // note the order here is different from line above.

        vm.startPrank(user);
        accountOps.withdraw{value: sendFee.nativeFee}(params, signature, extraOptions);
        vm.stopPrank();
        verifyPackets(bEid, addressToBytes32(address(depositCrossB)));

        assertEq(depositCrossB.getDepositAmount(issuer1NftAddress, tokenId, address(weth)), 0.8 * 10**18);
    }

    function getIssuersSig(
        OperationsContract accountOpsContract,
        OperationsContract.WithdrawParams memory params
    ) private view returns (bytes memory) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("AccountOperations")),
                keccak256(bytes("1")),
                31337,
                address(accountOpsContract)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
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
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuer1Pk, digest);
        return abi.encodePacked(r, s, v);
    }
}