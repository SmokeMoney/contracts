// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console for logging
import "../src/CoreNFTContract.sol";
import "../src/archive/weth.sol";
import "../src/archive/siggen.sol";
import "../src/SmokeSpendingContract.sol";
import "../src/SmokeDepositContract.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract BorrowTest is TestHelperOz5 {
    using ECDSA for bytes32;

    CoreNFTContract public nftContract;
    SmokeSpendingContract public lendingcontract;

    SignatureGenerator public siggen;
    WETH public weth;
    address public owner;
    address public issuer;
    uint256 internal issuerPk;
    address public user;
    uint256 internal userPk;
    address public user2;
    uint256 internal user2Pk;
    address public user3;
    address public user4 = address(4);
    uint256 signatureValidity = 2 minutes;

    uint32 aEid = 1;
    uint32 bEid = 2;

    uint256 public tokenId;
    uint256 public adminChainIdReal;

    function setUp() public virtual override {
        issuer = 0xE0D6f93151091f24EA09474e9271BD60F2624d99;
        issuerPk = vm.envUint("PRIVATE_KEY");
        (user, userPk) = makeAddrAndKey("user");
        (user2, user2Pk) = makeAddrAndKey("user2");

        owner = address(this);
        user3 = address(3);
        adminChainIdReal = 1;

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);
        vm.startPrank(issuer);
        nftContract = new CoreNFTContract(
            "AutoGas",
            "OG",
            issuer,
            0.02 * 1e18,
            10
        );
        weth = new WETH();
        siggen = new SignatureGenerator();
        lendingcontract = new SmokeSpendingContract(address(weth), address(owner));

        vm.stopPrank();

        lendingcontract.addIssuer(
            address(nftContract),
            issuer,
            1000,
            1e15,
            5e14,
            2
        );

        vm.startPrank(issuer);

        nftContract.approveChain(adminChainIdReal); // Adding a supported chain

        vm.deal(issuer, 100 ether);
        // Lending contract setup
        uint256 poolDepositAmount = 80 ether;
        lendingcontract.poolDeposit{value: poolDepositAmount}(
            address(nftContract)
        );
        vm.stopPrank();
        // assertEq(nftContract.adminChainId(), adminChainIdReal);

        // The user is getting some WETH
        vm.deal(user, 100 ether);
        // vm.deal(user2, 0.100 ether);
        vm.deal(user3, 51 ether);
        // vm.deal(user2, 100 ether);
        vm.startPrank(user);
        uint256 amount = 10 ether;
        weth.deposit{value: amount}();

        // User mints the NFT and user setup
        tokenId = nftContract.mint{value: 0.02 * 1e18}();
        vm.stopPrank();

        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();

        // Mint an NFT for the user
        vm.startPrank(user2);
        neighborhoodBorrow(
            lendingcontract,
            user2,
            address(nftContract),
            tokenId,
            uint256(0.01 * 10 ** 18),
            timestamp,
            signatureValidity,
            uint256(0),
            false
        );
        weth.deposit{value: 0.0095 * 10 ** 18}();
        vm.stopPrank();

        // vm.startPrank(issuer);
        // lendingcontract.setBorrowFees(address(nftContract), 0.00001 * 1e18);
        // vm.stopPrank();
    }

    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 public constant BORROW_TYPEHASH = keccak256(
        "Borrow(address borrower,address issuerNFT,uint256 nftId,uint256 amount,uint256 timestamp,uint256 signatureValidity,uint256 nonce,bool weth)"
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

    function neighborhoodBorrowWithSig(
        SmokeSpendingContract lendingContract,
        address recipeint,
        address issuerNFT,
        uint256 nftId,
        uint256 amount,
        uint256 timestamp,
        uint256 signatureValidityVar,
        uint256 nonce,
        bool wethBool,
        bool repayGas
    ) public {

        bytes memory userSignature = getUsersSig(
            lendingContract,
            recipeint,
            issuerNFT,
            nftId,
            amount,
            timestamp,
            signatureValidityVar,
            nonce
        );

        bytes memory issuersSignature = getIssuersSig2(
            lendingContract,
            recipeint,
            issuerNFT,
            nftId,
            amount,
            timestamp,
            signatureValidityVar,
            nonce
        );

        SmokeSpendingContract.BorrowParams memory params = SmokeSpendingContract
            .BorrowParams({
                issuerNFT: issuerNFT,
                nftId: nftId,
                amount: amount,
                timestamp: timestamp,
                signatureValidity: signatureValidityVar,
                nonce: nonce,
                weth: wethBool,
                repayGas: repayGas,
                recipient: recipeint
            });

        lendingContract.borrowWithSignature(
            params,
            userSignature, 
            issuersSignature
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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function getIssuersSig2(
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
                421614,
                0x9F1b8D30D9e86B3bF65fa9f91722B4A3E9802382
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                BORROW_TYPEHASH,
                borrower,
                issuerNFT,
                0,
                amount,
                1724995549,
                120,
                0
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
        console.logBytes(abi.encodePacked(r, s, v));
        return abi.encodePacked(r, s, v);
    }

    function getUsersSig(
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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function testBorrow() public {
        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();

        // Mint an NFT for the user
        vm.startPrank(user2);
        neighborhoodBorrow(
            lendingcontract,
            user2,
            address(nftContract),
            tokenId,
            uint256(25 * 10 ** 18),
            timestamp,
            signatureValidity,
            uint256(1),
            false
        );
        vm.stopPrank();
        console.log("blockstamp", timestamp);
        // assertEq(lendingcontract.getBorrowPosition(address(nftContract), tokenId, user2), -25 * 10**18);
        console.log(
            "user debt",
            lendingcontract.getBorrowPosition(address(nftContract), tokenId, user2)
        );

        vm.warp(1720962298);
        timestamp = vm.getBlockTimestamp();

        vm.startPrank(user2);
        neighborhoodBorrow(
            lendingcontract,
            user2,
            address(nftContract),
            tokenId,
            uint256(25 * 10 ** 18),
            timestamp,
            signatureValidity,
            uint256(2),
            false
        );
        vm.stopPrank();
        console.log("blockstamp", timestamp);
        console.log(
            "user debt",
            lendingcontract.getBorrowPosition(address(nftContract), tokenId, user2)
        );

        vm.startPrank(user3);
        lendingcontract.repay{value: 25 ether}(
            address(nftContract),
            tokenId,
            address(user2),
            address(user3)
        );
        vm.stopPrank();
        console.log("");
        console.log(
            "user debt",
            lendingcontract.getBorrowPosition(address(nftContract), tokenId, user2)
        );
        console.log(
            "Borrow pos",
            lendingcontract.getBorrowPosition(
                address(nftContract),
                tokenId,
                user2
            )
        );
        vm.warp(1720962398);

        vm.warp(1720962498);

        vm.warp(1720962548);

        console.log("");
        console.log(
            "user debt",
            lendingcontract.getBorrowPosition(address(nftContract), tokenId, user2)
        );
        console.log(
            "Borrow pos",
            lendingcontract.getBorrowPosition(
                address(nftContract),
                tokenId,
                user2
            )
        );
        vm.startPrank(user3);
        lendingcontract.repay{value: 25.000017202568039109 ether}(
            address(nftContract),
            tokenId,
            address(user2),
            address(user3)
        );
        vm.stopPrank();
        console.log("FULLY REPAID");
        console.log("");
        console.log("");
        console.log(
            "user debt",
            lendingcontract.getBorrowPosition(address(nftContract), tokenId, user2)
        );
        console.log(
            "Borrow pos",
            lendingcontract.getBorrowPosition(
                address(nftContract),
                tokenId,
                user2
            )
        );
        console.log("");
        vm.warp(1720962598);
        vm.warp(1720962698);
        console.log(
            "user debt",
            lendingcontract.getBorrowPosition(address(nftContract), tokenId, user2)
        );
        console.log(
            "Borrow pos",
            lendingcontract.getBorrowPosition(
                address(nftContract),
                tokenId,
                user2
            )
        );
        console.log("");
        console.log("after 13 years");
        vm.warp(2131105470);
        console.log(
            "user debt",
            lendingcontract.getBorrowPosition(address(nftContract), tokenId, user2)
        );
        console.log(
            "Total Borrow pos",
            lendingcontract.getBorrowPosition(
                address(nftContract),
                tokenId,
                user2
            )
        );

        console.log("After multi borrows", address(42).balance);
    }

    function testBorrow2() public {
        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        // Mint an NFT for the user
        vm.startPrank(user2);
        neighborhoodBorrow(
            lendingcontract,
            user2,
            address(nftContract),
            tokenId,
            uint256(25 * 10 ** 18),
            timestamp,
            signatureValidity,
            uint256(1),
            false
        );
        vm.stopPrank();
    }

    function testBorrowGasless() public {
        vm.warp(1724993588);
        uint256 timestamp = vm.getBlockTimestamp();
        // Mint an NFT for the user
        vm.startPrank(issuer);
        neighborhoodBorrowWithSig(lendingcontract, 0xa2A53973a147F2996F3f33c363Af0f22Dc46c549, 0x34e7CEBC535C30Aceeb63a63C20b0C42A80B215A, 0, 0.00042 * 10 ** 18, timestamp, 120, 0, false, true);
        vm.stopPrank();
    }

    function testRepay() public {
        vm.startPrank(user3);
        lendingcontract.repay{value: 0.001 ether}(
            address(nftContract),
            tokenId,
            address(user2),
            address(user3)
        );
        vm.stopPrank();
    }

    function testMultiRepayment() public {
        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();

        // Mint an NFT for the user
        vm.startPrank(user2);
        neighborhoodBorrow(
            lendingcontract,
            user2,
            address(nftContract),
            tokenId,
            uint256(25 * 10 ** 18),
            timestamp,
            signatureValidity,
            uint256(1),
            false
        );
        vm.stopPrank();

        vm.warp(1720962281);

        timestamp = vm.getBlockTimestamp();
        vm.txGasPrice(1);
        vm.startPrank(issuer);
        neighborhoodBorrowWithSig(lendingcontract, user, address(nftContract), tokenId, 10 * 10 ** 18, timestamp, signatureValidity, 2, false, true);
        vm.stopPrank();

        vm.warp(1720963281);
        vm.prank(issuer);
        lendingcontract.triggerAutogas(address(nftContract), tokenId, user4);

        vm.txGasPrice(2);
        vm.warp(1720963281);
        timestamp = vm.getBlockTimestamp();

        vm.startPrank(user3);
        tokenId = nftContract.mint{value: 0.02 * 1e18}();
        neighborhoodBorrow(
            lendingcontract,
            user3,
            address(nftContract),
            tokenId,
            uint256(10 * 10 ** 18),
            timestamp,
            signatureValidity,
            uint256(0),
            false
        );

        uint256[] memory borrowAmounts = new uint256[](4);
        borrowAmounts[0] = lendingcontract.getBorrowPosition(
            address(nftContract),
            1,
            user
        );
        borrowAmounts[1] = lendingcontract.getBorrowPosition(
            address(nftContract),
            1,
            user2
        );
        borrowAmounts[2] = lendingcontract.getBorrowPosition(
            address(nftContract),
            2,
            user3
        );
        borrowAmounts[3] = lendingcontract.getBorrowPosition(
            address(nftContract),
            1,
            user4
        );

        address[] memory issuerNFTs = new address[](4);
        issuerNFTs[0] = address(nftContract);
        issuerNFTs[1] = address(nftContract);
        issuerNFTs[2] = address(nftContract);
        issuerNFTs[3] = address(nftContract);

        uint256[] memory nftIds = new uint256[](4);
        nftIds[0] = 1;
        nftIds[1] = 1;
        nftIds[2] = 2;
        nftIds[3] = 1;

        address[] memory walletAddresses = new address[](4);
        walletAddresses[0] = user;
        walletAddresses[1] = user2;
        walletAddresses[2] = user3;
        walletAddresses[3] = user4;
        uint256 totalBorrowed = 0;
        for (uint i; i < borrowAmounts.length; i++) {
            totalBorrowed += borrowAmounts[i];
        }

        lendingcontract.repayMultiple{value: totalBorrowed}(
            issuerNFTs,
            nftIds,
            walletAddresses,
            borrowAmounts,
            user3
        );

        vm.stopPrank();
        console.log("After multirepayment", address(42).balance);
    }

    function testAutoGas() public {
        vm.fee(25 gwei);
        vm.txGasPrice(1);

        console.log("issuer balance", issuer.balance);
        vm.startPrank(issuer);
        lendingcontract.triggerAutogas(address(nftContract), tokenId, user2);
        console.log("issuer balance", issuer.balance);
        console.log(user2.balance);
        vm.stopPrank();

        vm.startPrank(user2);
        weth.deposit{value: 0.00095 * 10 ** 18}();
        vm.stopPrank();

        vm.startPrank(issuer);
        console.log(user2.balance);
        vm.txGasPrice(2);
        lendingcontract.triggerAutogasSpike(
            address(nftContract),
            tokenId,
            user2
        );
        vm.stopPrank();
        vm.startPrank(issuer);
        console.log("After autogas", address(42).balance);
    }
}
