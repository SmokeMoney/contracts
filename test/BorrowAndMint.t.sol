// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console for logging
import "../src/CoreNFTContract.sol";
import "../src/archive/weth.sol";
import "../src/archive/siggen.sol";
import "../src/SmokeSpendingContract.sol";
import "../src/SpendingConfig.sol";
import "../src/BorrowAndMint.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";


import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract SimpleNFT is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    uint256 public constant MINT_PRICE = 0.002 ether;
    uint256 public constant MAX_SUPPLY = 1000;

    constructor() ERC721("Smoke NFT Optimism", "SNFT") Ownable(msg.sender) {}

    function mint() public payable returns (uint256) {
        require(msg.value >= MINT_PRICE, "Insufficient payment");
        require(_tokenIds.current() < MAX_SUPPLY, "Max supply reached");

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _safeMint(msg.sender, newTokenId);
        return newTokenId;
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIds.current();
    }
}

contract BorrowTest is TestHelperOz5 {
    using ECDSA for bytes32;

    BorrowAndMintNFT public borrowAndM;
    CoreNFTContract public nftContract;
    SmokeSpendingContract public lendingcontract;
    SimpleNFT public smokeNFT;
    SpendingConfig public spendingConfig;

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


    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 private constant BORROW_TYPEHASH = keccak256(
        "Borrow(address borrower,address issuerNFT,uint256 nftId,uint256 amount,uint256 timestamp,uint256 signatureValidity,uint256 nonce,address recipient)"
    );


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
        smokeNFT = new SimpleNFT();
        borrowAndM = new BorrowAndMintNFT(address(lendingcontract), address(smokeNFT));
        spendingConfig = new SpendingConfig(owner, address(lendingcontract));
        vm.stopPrank();
        
        vm.startPrank(owner);
        lendingcontract.setSpendingConfigContract(address(spendingConfig));
        spendingConfig.setMaxRepayGas(0.002*1e18);
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
        tokenId = nftContract.mint{value: 0.02 * 1e18}(0);
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
            false,
            user2
        );
        vm.stopPrank();
    }


    function testBorrow() public {
        vm.prank(user);
        smokeNFT.mint{value:0.002 * 1e18}();
        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        uint256 nonce = lendingcontract.getCurrentNonce(address(nftContract), tokenId);
        
        console.log(address(smokeNFT));
        bytes memory userSignature = getUsersSig(
            lendingcontract,
            user,
            address(nftContract),
            tokenId,
            0.002 * 1e18,
            timestamp,
            1200,
            nonce,
            address(borrowAndM)
        );
        bytes memory issuersSignature = getIssuersSig(
            lendingcontract,
            user,
            address(nftContract),
            tokenId,
            0.002 * 1e18,
            timestamp,
            1200,
            nonce,
            address(borrowAndM)
        );
        IBorrowContract.BorrowParams memory params = IBorrowContract
        .BorrowParams({
            borrower: user,
            issuerNFT: address(nftContract),
            nftId: tokenId,
            amount: 0.002 * 1e18,
            timestamp: timestamp,
            signatureValidity: 1200,
            nonce: nonce,
            repayGas: 200000000000000,
            weth: false,
            recipient: address(borrowAndM),
            integrator: 0
        });

        vm.startPrank(user2);
        console.log(user2.balance);
        borrowAndM.borrowAndMint(params, userSignature, issuersSignature);
        console.log(user.balance);
        console.log(smokeNFT.balanceOf(user));
        borrowAndM.justMint{value:0.002 * 1e18}(0.002 * 1e18);
        vm.stopPrank();
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
        bool wethBool,
        address recipient
    ) public {
        bytes memory signature = getIssuersSig(
            lendingContract,
            userAddress,
            issuerNFT,
            nftId,
            amount,
            timestamp,
            signatureValidityVar,
            nonce,
            recipient
        );

        lendingContract.borrow(
            issuerNFT,
            nftId,
            amount,
            timestamp,
            signatureValidityVar,
            nonce,
            recipient,
            wethBool,
            signature,
            0
        );
    }

    function neighborhoodBorrowWithSig(
        SmokeSpendingContract lendingContract,
        address borrower,
        address issuerNFT,
        uint256 nftId,
        uint256 amount,
        uint256 timestamp,
        uint256 signatureValidityVar,
        uint256 nonce,
        uint256 repayGas,
        bool wethBool,
        address recipient
    ) public {

        bytes memory userSignature = getUsersSig(
            lendingContract,
            borrower,
            issuerNFT,
            nftId,
            amount,
            timestamp,
            signatureValidityVar,
            nonce,
            recipient
        );

        bytes memory issuersSignature = getIssuersSig(
            lendingContract,
            borrower,
            issuerNFT,
            nftId,
            amount,
            timestamp,
            signatureValidityVar,
            nonce,
            recipient
        );

        SmokeSpendingContract.BorrowParams memory params = SmokeSpendingContract
            .BorrowParams({
                borrower: borrower,
                issuerNFT: issuerNFT,
                nftId: nftId,
                amount: amount,
                timestamp: timestamp,
                signatureValidity: signatureValidityVar,
                nonce: nonce,
                repayGas: repayGas,
                weth: wethBool,
                recipient: recipient,
                integrator: 0
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
                BORROW_TYPEHASH,
                borrower,
                issuerNFT,
                nftId,
                amount,
                timestamp,
                signatureValidityVar,
                nonce,
                recipient
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, digest);
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
                BORROW_TYPEHASH,
                borrower,
                issuerNFT,
                nftId,
                amount,
                timestamp,
                signatureValidityVar,
                nonce,
                recipient
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, digest);
        return abi.encodePacked(r, s, v);
    }
}