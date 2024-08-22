// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/deposit.sol";
import "../src/corenft.sol";
import "../src/accountops.sol";
import "../src/wstETHOracleReceiver.sol";
import "../src/archive/weth.sol";
import "../src/archive/siggen.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";   

import "./Setup.t.sol";

contract DepositTest is Setup {
    using ECDSA for bytes32;


    function setUp() public virtual override {

        super.setUp();
    }

    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 private constant WITHDRAW_TYPEHASH = keccak256(
        "Withdraw(address issuerNFT,bytes32 token,uint256 nftId,uint256 amount,uint32 targetChainId,uint256 timestamp,uint256 nonce,bool primary,bytes32 recipientAddress)"
    );

    function testDeposit() public {
        // Mint an NFT for the user
        vm.startPrank(user);
        uint256 tokenId = issuer1NftContract.mint{value:0.02*1e18}();
        depositLocal.deposit(issuer1NftAddress, address(weth), tokenId, 1 * 10**18);
        vm.stopPrank();

        assertEq(depositLocal.getDepositAmount(issuer1NftAddress, tokenId, address(weth)), 1 * 10**18);
    }

    // Add more test cases here, for example:
    function testWithdraw() public {
        // Mint an NFT for the user
        vm.startPrank(user);
        uint256 tokenId = issuer1NftContract.mint{value:0.02*1e18}();
        depositLocal.deposit(issuer1NftAddress, address(weth), tokenId, 1 * 10**18);
        vm.stopPrank();

        uint timestamp = vm.unixTime();

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

        bytes memory signature = getIssuersSig(
            accountOps,
            params
        );

        bytes memory options = new bytes(0);
        vm.startPrank(user);
        accountOps.withdraw(params, signature, options);
        vm.stopPrank();
        assertEq(depositLocal.getDepositAmount(issuer1NftAddress, tokenId, address(weth)), 0.9 * 10**18);
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