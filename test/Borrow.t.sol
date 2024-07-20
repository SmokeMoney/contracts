// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console for logging
import "../src/nftaccounts.sol";
import "../src/weth.sol";
import "../src/siggen.sol";
import "../src/lendingcontract.sol";
import "../src/deposit.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract DepositTest is TestHelperOz5 {
    using ECDSA for bytes32;

    CrossChainLendingAccount public nftContract;    
    CrossChainLendingContract public lendingcontract;

    SignatureGenerator public siggen;
    WETH public weth;
    MockERC20 public mockToken;
    address public issuer;
    uint256 internal issuerPk;
    address public user;
    uint256 internal userPk;
    address public user2;
    uint256 internal user2Pk;
    address public user3;


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

        nftContract = new CrossChainLendingAccount("AutoGas", "OG", issuer, endpoints[aEid], issuer, 1);
        weth = new WETH();
        siggen = new SignatureGenerator();
        lendingcontract = new CrossChainLendingContract(issuer, address(weth), aEid);

        nftContract.approveChain(adminChainIdReal); // Adding a supported chain

        vm.deal(issuer, 100 ether);
        // Lending contract setup
        uint256 poolDepositAmount = 80 ether;
        lendingcontract.poolDeposit{value: poolDepositAmount}(poolDepositAmount);

        vm.stopPrank();
        assertEq(nftContract.adminChainId(), adminChainIdReal);

        // The user is getting some WETH
        vm.deal(user, 100 ether);
        vm.deal(user3, 51 ether);
        // vm.deal(user2, 100 ether);
        vm.startPrank(user);
        uint256 amount = 10 ether;
        weth.deposit{value: amount}();

        // User mints the NFT and user setup
        tokenId = nftContract.mint();
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
        vm.stopPrank();

    }


    function testBorrow() public {
        // Check if user2 is in the list of approved wallets
        // address[] memory approvedWallets = nftContract.getApprovedWallets(tokenId);
        // bool isUser2Approved = false;

        // for (uint i = 0; i < approvedWallets.length; i++) {
        //     if (approvedWallets[i] == user2) {
        //         isUser2Approved = true;
        //         break;
        //     }
        // }
        // assertTrue(isUser2Approved, "user2 should be in the list of approved wallets");

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
        lendingcontract.repay{value: 25 ether}(tokenId);
        vm.stopPrank();
        console.log("");
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2)); 
        console.log("Borrow pos", lendingcontract.getBorrowPosition(tokenId, user2));
        console.log("Repay  pos", lendingcontract.getRepayPosition(tokenId));
        vm.warp(1720962398);

        vm.warp(1720962498);

        vm.warp(1720962548);

        console.log("");
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2)); 
        console.log("Borrow pos", lendingcontract.getBorrowPosition(tokenId, user2));
        console.log("Repay  pos", lendingcontract.getRepayPosition(tokenId));
        vm.startPrank(user3);
        lendingcontract.repay{value: 25.500017202568039109 ether}(tokenId);
        vm.stopPrank(); 
        console.log("FULLY REPAID");
        console.log("");
        console.log("");
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2)); 
        console.log("Borrow pos", lendingcontract.getBorrowPosition(tokenId, user2));
        console.log("Repay  pos", lendingcontract.getRepayPosition(tokenId));
        console.log("");
        vm.warp(1720962598);
        vm.warp(1720962698);
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2)); 
        console.log("Borrow pos", lendingcontract.getBorrowPosition(tokenId, user2));
        console.log("Repay  pos", lendingcontract.getRepayPosition(tokenId));
        console.log("");
        console.log("after 13 years");
        vm.warp(2131105470);
        console.log("user debt", lendingcontract.getNetPosition(tokenId, user2)); 
        console.log("Total Borrow pos", lendingcontract.getBorrowPosition(tokenId, user2));
        console.log("Repay  pos", lendingcontract.getRepayPosition(tokenId));

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
        lendingcontract.repay{value: 0.001 ether}(tokenId);
        vm.stopPrank();
        
    }

}
