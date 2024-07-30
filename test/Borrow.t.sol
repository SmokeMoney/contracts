// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console for logging
import "../src/corenft.sol";
import "../src/weth.sol";
import "../src/siggen.sol";
import "../src/lendingcontract.sol";
import "../src/deposit.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";


contract DepositTest is TestHelperOz5 {
    using ECDSA for bytes32;

    CoreNFTContract public nftContract;    
    CrossChainLendingContract public lendingcontract;

    SignatureGenerator public siggen;
    WETH public weth;
    address public issuer;
    uint256 internal issuerPk;
    address public user;
    uint256 internal userPk;
    address public user2;
    uint256 internal user2Pk;
    address public user3;
    address public user4 = address(4);


    uint32 aEid = 1;
    uint32 bEid = 2;
    
    uint256 public tokenId;
    uint256 public adminChainIdReal;

    function setUp() public virtual override {

        (issuer, issuerPk) = makeAddrAndKey("issuer");
        (user, userPk) = makeAddrAndKey("user");
        (user2, user2Pk) = makeAddrAndKey("user2");

        user3 = address(3);
        adminChainIdReal = 1;
        
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        vm.startPrank(issuer);

        nftContract = new CoreNFTContract("AutoGas", "OG", issuer, issuer, 0.02 * 1e18, 10);
        weth = new WETH();
        siggen = new SignatureGenerator();
        lendingcontract = new CrossChainLendingContract(issuer, address(weth), aEid);

        nftContract.approveChain(adminChainIdReal); // Adding a supported chain

        vm.deal(issuer, 100 ether);
        
        // Lending contract setup
        uint256 poolDepositAmount = 80 ether;
        lendingcontract.poolDeposit{value: poolDepositAmount}(poolDepositAmount);

        vm.stopPrank();
        // assertEq(nftContract.adminChainId(), adminChainIdReal);

        // The user is getting some WETH
        vm.deal(user, 100 ether);
        vm.deal(user3, 51 ether);
        // vm.deal(user2, 100 ether);
        vm.startPrank(user);
        uint256 amount = 10 ether;
        weth.deposit{value: amount}();

        // User mints the NFT and user setup
        tokenId = nftContract.mint{value:0.02*1e18}();
        vm.stopPrank();


        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        vm.startPrank(issuer);
        bytes32 digest = keccak256(abi.encodePacked(user2, tokenId, uint256(0.01 * 10**18), timestamp, uint256(0), uint256(adminChainIdReal)));
        bytes32 hash = siggen.getEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, hash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();
        
        // Mint an NFT for the user
        vm.startPrank(user2);
        lendingcontract.borrow(tokenId, uint256(0.01 * 10**18), timestamp, uint256(0), signature);
        weth.deposit{value: 0.0095 * 10**18}();
        vm.stopPrank();

        vm.startPrank(issuer);
        lendingcontract.setBorrowFees(0.00001*1e18);
        lendingcontract.setBorrowFeeRecipient(address(42));
        vm.stopPrank();

    }


    function testBorrow() public {
        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        vm.startPrank(issuer);
        bytes32 digest = keccak256(abi.encodePacked(user2, tokenId, uint256(25 * 10**18), timestamp, uint256(1), uint256(adminChainIdReal)));
        bytes32 hash = siggen.getEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, hash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();
        
        // Mint an NFT for the user
        vm.startPrank(user2);
        lendingcontract.borrow(tokenId, uint256(25 * 10**18), timestamp, uint256(1), signature);
        vm.stopPrank();
        console.log("blockstamp", timestamp);
        // assertEq(lendingcontract.getNetPosition(tokenId, user2), -25 * 10**18);
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2));   
        
        vm.warp(1720962298);
        timestamp = vm.getBlockTimestamp();
        vm.startPrank(issuer);
        digest = keccak256(abi.encodePacked(user2, tokenId, uint256(25 * 10**18), timestamp, uint256(2), uint256(adminChainIdReal)));
        hash = siggen.getEthSignedMessageHash(digest);
        (v, r, s) = vm.sign(issuerPk, hash);
        signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();

        vm.startPrank(user2);
        lendingcontract.borrow(tokenId, uint256(25 * 10**18), timestamp, uint256(2), signature);
        vm.stopPrank();
        console.log("blockstamp", timestamp);
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2));   

        vm.startPrank(user3);
        lendingcontract.repay{value: 25 ether}(tokenId, address(user2), address(user3));
        vm.stopPrank();
        console.log("");
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2)); 
        console.log("Borrow pos", lendingcontract.getBorrowPosition(tokenId, user2));
        vm.warp(1720962398);

        vm.warp(1720962498);

        vm.warp(1720962548);

        console.log("");
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2)); 
        console.log("Borrow pos", lendingcontract.getBorrowPosition(tokenId, user2));
        vm.startPrank(user3);
        lendingcontract.repay{value: 25.500017202568039109 ether}(tokenId, address(user2), address(user3));
        vm.stopPrank(); 
        console.log("FULLY REPAID");
        console.log("");
        console.log("");
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2)); 
        console.log("Borrow pos", lendingcontract.getBorrowPosition(tokenId, user2));
        console.log("");
        vm.warp(1720962598);
        vm.warp(1720962698);
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2)); 
        console.log("Borrow pos", lendingcontract.getBorrowPosition(tokenId, user2));
        console.log("");
        console.log("after 13 years");
        vm.warp(2131105470);
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2)); 
        console.log("Total Borrow pos", lendingcontract.getBorrowPosition(tokenId, user2));

        console.log("After multi borrows        ", address(42).balance);
    }

    function testBorrow2() public {

        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        vm.startPrank(issuer);
        bytes32 digest = keccak256(abi.encodePacked(user2, tokenId, uint256(25 * 10**18), timestamp, uint256(1), uint256(adminChainIdReal)));
        bytes32 hash = siggen.getEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, hash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();
        
        // Mint an NFT for the user
        vm.startPrank(user2);
        lendingcontract.borrow(tokenId, uint256(25 * 10**18), timestamp, uint256(1), signature);
        vm.stopPrank();
    }


    function testRepay() public {
        vm.startPrank(user3);
        lendingcontract.repay{value: 0.001 ether}(tokenId, address(user2), address(user3));
        vm.stopPrank();
        
    }

    function testMultiRepayment() public {

        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        vm.startPrank(issuer);
        bytes32 digest = keccak256(abi.encodePacked(user2, tokenId, uint256(25 * 10**18), timestamp, uint256(1), uint256(adminChainIdReal)));
        bytes32 hash = siggen.getEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, hash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();
        
        // Mint an NFT for the user
        vm.startPrank(user2);
        lendingcontract.borrow(tokenId, uint256(25 * 10**18), timestamp, uint256(1), signature);
        vm.stopPrank();


        vm.warp(1720962281);
        timestamp = vm.getBlockTimestamp();
        vm.startPrank(issuer);
        digest = keccak256(abi.encodePacked(user, tokenId, uint256(10 * 10**18), timestamp, uint256(2), uint256(adminChainIdReal)));
        hash = siggen.getEthSignedMessageHash(digest);
        (v, r, s) = vm.sign(issuerPk, hash);
        signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();

        timestamp = vm.getBlockTimestamp();
        vm.startPrank(user);
        digest = keccak256(abi.encodePacked(user, tokenId, uint256(10 * 10**18), timestamp, uint256(2), uint256(adminChainIdReal)));
        hash = siggen.getEthSignedMessageHash(digest);
        (v, r, s) = vm.sign(userPk, hash);
        bytes memory userSignature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();
        
        
        vm.txGasPrice(1);
        vm.startPrank(issuer);
        lendingcontract.borrowWithSignature(tokenId, uint256(10 * 10**18), timestamp, uint256(2), user, userSignature, signature);
        vm.stopPrank();

        vm.warp(1720963281);
        vm.prank(issuer);
        lendingcontract.triggerAutogas(tokenId, user4);

        vm.txGasPrice(2);
        vm.warp(1720963281);
        timestamp = vm.getBlockTimestamp();
        vm.startPrank(issuer);
        digest = keccak256(abi.encodePacked(user3, uint256(2), uint256(10 * 10**18), timestamp, uint256(0), uint256(adminChainIdReal)));
        hash = siggen.getEthSignedMessageHash(digest);
        (v, r, s) = vm.sign(issuerPk, hash);
        signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();

        vm.startPrank(user3);
        tokenId = nftContract.mint{value:0.02*1e18}();
        lendingcontract.borrow(tokenId, uint256(10 * 10**18), timestamp, uint256(0), signature);
        uint256[] memory borrowAmounts = new uint256[](4);
        borrowAmounts[0] = lendingcontract.getBorrowPosition(1, user);
        borrowAmounts[1] = lendingcontract.getBorrowPosition(1, user2);
        borrowAmounts[2] = lendingcontract.getBorrowPosition(2, user3);
        borrowAmounts[3] = lendingcontract.getBorrowPosition(1, user4);

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
        for (uint i; i< borrowAmounts.length; i++) {
            totalBorrowed+=borrowAmounts[i];
        }

        lendingcontract.repayMultiple{value: totalBorrowed}(nftIds, walletAddresses, borrowAmounts, user3);

        vm.stopPrank();
        console.log("After multirepayment", address(42).balance);
    }

    function testAutoGas() public {
        vm.fee(25 gwei);
        vm.txGasPrice(1);

        console.log("issuer balance", issuer.balance);
        vm.startPrank(issuer);
        lendingcontract.triggerAutogas(tokenId, user2);
        console.log("issuer balance", issuer.balance);
        console.log(user2.balance);
        vm.stopPrank();


        vm.startPrank(user2);
        weth.deposit{value: 0.00095 * 10**18}();
        vm.stopPrank();

        vm.startPrank(issuer);
        console.log(user2.balance);
        vm.txGasPrice(2);
        lendingcontract.triggerAutogasSpike(tokenId, user2);
        vm.stopPrank();
        vm.startPrank(issuer);
        console.log("After autogas", address(42).balance);
    }
}
