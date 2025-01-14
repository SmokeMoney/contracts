// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/src/Test.sol";
import "./Setup.t.sol";
import "../src/SmokeDepositContract.sol";
import "../src/CoreNFTContract.sol";
import "../src/OperationsContract.sol";
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

    SmokeDepositContract public depositCross;

    bytes32 private constant SET_LOWER_LIMIT_TYPEHASH = keccak256(
        "SetLowerLimit(uint256 nftId,bytes32 wallet,uint256 chainId,uint256 newLimit,uint256 timestamp,uint256 nonce)"
    );

    bytes32 private constant SET_LOWER_BULK_LIMITS_TYPEHASH = keccak256(
        "SetLowerBulkLimits(uint256 nftId,bytes32 wallet,uint256[] chainIds,uint256[] newLimits,uint256 timestamp,uint256 nonce)"
    );

    bytes32 private constant RESET_WALLET_CHAIN_LIMITS_TYPEHASH =
        keccak256("ResetWalletChainLimits(uint256 nftId,bytes32 wallet,uint256 timestamp,uint256 nonce)");

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public virtual override {
        super.setUp();
        // super.setupRateLimits();
    }

    function testAddWallets() public {
        vm.startPrank(user);
        issuer1NftContract.setHigherLimit(tokenId, addressToBytes32(address(user)), aEid, 1 * 10 ** 18);

        uint256[] memory chainIds = new uint256[](3);
        chainIds[0] = aEid;
        chainIds[1] = bEid;
        chainIds[2] = cEid;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1.1 * 10 ** 18;
        amounts[1] = 2 * 10 ** 18;
        amounts[2] = 0.1 * 10 ** 18;

        bool[] memory autogas = new bool[](3);
        autogas[0] = true;
        autogas[1] = false;
        autogas[2] = true;

        issuer1NftContract.setHigherBulkLimits(tokenId, addressToBytes32(address(user)), chainIds, amounts, autogas);
        vm.stopPrank();
        console.log("set higher limits");
        console.log(issuer1NftContract.getWalletChainLimit(tokenId, addressToBytes32(address(user)), aEid));
        console.log(issuer1NftContract.getWalletChainLimit(tokenId, addressToBytes32(address(user)), bEid));
        console.log(issuer1NftContract.getWalletChainLimit(tokenId, addressToBytes32(address(user)), cEid));

        autogas = issuer1NftContract.getAutogasConfig(tokenId, addressToBytes32(user));
        assertEq(autogas[1], false);

        amounts[0] = 0.42 * 10 ** 18;
        amounts[1] = 0.69 * 10 ** 18;
        amounts[2] = 0.2 * 10 ** 18;

        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        vm.startPrank(issuer1);

        bytes32 structHash = keccak256(
            abi.encode(
                SET_LOWER_BULK_LIMITS_TYPEHASH,
                tokenId,
                addressToBytes32(user),
                keccak256(abi.encodePacked(chainIds)),
                keccak256(abi.encodePacked(amounts)),
                timestamp,
                uint256(0)
            )
        );

        bytes memory signature = getSignature(structHash);

        // bytes32 digest = keccak256(abi.encode(tokenId, addressToBytes32(user), abi.encode(chainIds), abi.encode(amounts), timestamp, uint256(0)));
        // bytes32 hash = siggen.getEthSignedMessageHash(digest);
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuer1Pk, hash);
        // bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();

        // console.logBytes32(digest);
        vm.startPrank(user);
        issuer1NftContract.setLowerBulkLimits(
            tokenId, addressToBytes32(user), chainIds, amounts, timestamp, 0, signature
        );
        console.log("set lower limits at", timestamp);
        console.log(issuer1NftContract.getWalletChainLimit(tokenId, addressToBytes32(address(user)), aEid));
        console.log(issuer1NftContract.getWalletChainLimit(tokenId, addressToBytes32(address(user)), bEid));
        console.log(issuer1NftContract.getWalletChainLimit(tokenId, addressToBytes32(address(user)), cEid));
        vm.stopPrank();

        vm.warp(1720963281);
        timestamp = vm.getBlockTimestamp();
        uint256 newlimit = 0.1 * 10 ** 18;

        structHash = keccak256(
            abi.encode(
                SET_LOWER_LIMIT_TYPEHASH, tokenId, addressToBytes32(user), uint256(3), newlimit, timestamp, uint256(1)
            )
        );

        signature = getSignature(structHash);

        vm.startPrank(user);
        issuer1NftContract.setLowerLimit(tokenId, addressToBytes32(user), 3, newlimit, timestamp, 1, signature);
        console.log("set lower limits at", timestamp);
        console.log(issuer1NftContract.getWalletChainLimit(tokenId, addressToBytes32(address(user)), cEid));
        vm.stopPrank();

        uint256[] memory newLimits = new uint256[](4);
        newLimits[0] = 0.42 * 10 ** 18;
        newLimits[1] = 0.69 * 10 ** 18;
        newLimits[2] = 0.2 * 10 ** 18;
        newLimits[3] = 2 * 10 ** 18;

        uint256[] memory chainIds2 = new uint256[](4);
        chainIds2[0] = aEid;
        chainIds2[1] = bEid;
        chainIds2[2] = cEid;
        chainIds2[3] = dEid;

        structHash = keccak256(
            abi.encode(RESET_WALLET_CHAIN_LIMITS_TYPEHASH, tokenId, addressToBytes32(user), timestamp, uint256(2))
        );

        signature = getSignature(structHash);

        vm.startPrank(user);
        issuer1NftContract.resetWalletChainLimits(tokenId, addressToBytes32(address(user)), timestamp, 2, signature);
        vm.stopPrank();
    }

    function getSignature(bytes32 structHash) private view returns (bytes memory) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("CoreNFTContract")),
                keccak256(bytes("1")),
                31337,
                address(issuer1NftContract)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuer1Pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function testMaxMint() public {
        vm.startPrank(userB);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        vm.expectRevert();
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        vm.stopPrank();
        vm.prank(issuer1);
        issuer1NftContract.setMaxNFTs(11);
        vm.startPrank(userB);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        vm.stopPrank();
        assertEq(tokenId, 12);
    }

    function testMinting() public {
        vm.startPrank(userB);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        vm.stopPrank();
    }

    function testBalanceWithdrawal() public {
        vm.startPrank(userB);
        tokenId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
        vm.stopPrank();
        vm.prank(issuer1);
        issuer1NftContract.withdrawFunds();
    }
}
