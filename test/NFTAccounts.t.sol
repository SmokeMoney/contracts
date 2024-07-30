// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/deposit.sol";
import "../src/corenft.sol";
import "../src/accountops.sol";
import "../src/weth.sol";
import "../src/siggen.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";

contract DepositTest is TestHelperOz5 {
    using ECDSA for bytes32;
    using OptionsBuilder for bytes;

    uint32 aEid = 1;
    uint32 bEid = 2;
    uint32 cEid = 3;
    uint32 dEid = 4;

    uint16 SEND = 1;
    uint16 SEND_ABA = 2;

    string public _a = "A";
    string public _b = "B";

    address public user = address(0x1);
    address public userB = address(0x2);

    AdminDepositContract public depositLocal;
    AdminDepositContract public depositCross;
    CoreNFTContract public nftContract;
    OperationsContract public accountOps;
    SignatureGenerator public siggen;
    WETH public weth;
    address public issuer;
    address public user2  = address(3);
    uint256 internal issuerPk;
    uint256 tokenId;


    function setUp() public virtual override {
        (issuer, issuerPk) = makeAddrAndKey("issuer");

        vm.deal(userB, 1000 ether);
        // The user is getting some WETH
        vm.deal(user, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(issuer, 100 ether);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);
        
        nftContract = new CoreNFTContract("AutoGas", "OG", issuer, address(this), 0.02 * 1e18, 10);
        accountOps = OperationsContract(
            payable(_deployOApp(type(OperationsContract).creationCode, abi.encode(address(nftContract), address(endpoints[aEid]), address(0), address(issuer), address(this), 1)))
        );

        depositLocal = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(accountOps), address(0), address(0), address(0), 1, aEid, address(endpoints[aEid]), address(issuer), address(this))))
        );

        depositCross = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(accountOps), address(0), address(0), address(0), 1, bEid, address(endpoints[bEid]), address(issuer), address(this))))
        );
        
        address[] memory oapps = new address[](2);
        oapps[0] = address(accountOps);
        oapps[1] = address(depositCross);
        this.wireOApps(oapps);
        
        vm.startPrank(issuer);
        
        weth = new WETH();
        siggen = new SignatureGenerator();
        
        depositCross.addSupportedToken(address(weth));
        depositLocal.addSupportedToken(address(weth));

        nftContract.approveChain(aEid); // Adding a supported chain
        nftContract.approveChain(bEid); // Adding a supported chain
        nftContract.approveChain(cEid); // Adding a supported chain
        nftContract.approveChain(dEid); // Adding a supported chain
        accountOps.setDepositContract(aEid, address(depositLocal)); // Adding the deposit contract on the local chain
        accountOps.setDepositContract(bEid, address(depositCross)); // Adding the deposit contract on a diff chain
        vm.stopPrank();

        assertEq(accountOps.adminChainId(), aEid);

        vm.startPrank(user);
        uint256 amount = 10 ether;
        weth.deposit{value: amount}();
        weth.approve(address(depositLocal), 10 * 10**18);
        weth.approve(address(depositCross), 10 * 10**18);
        tokenId = nftContract.mint{value:0.02*1e18}();
        depositLocal.deposit(address(weth), tokenId, 1 * 10**18);
        depositCross.deposit(address(weth), tokenId, 1 * 10**18);
        vm.stopPrank();
        assertEq(depositCross.getDepositAmount(address(weth), tokenId), 1 * 10**18);
    }

    function testAddWallets() public {

        vm.startPrank(user);
        nftContract.setHigherLimit(tokenId, address(user), aEid, 1 * 10**18);

        uint256[] memory chainIds = new uint256[](3);
        chainIds[0] = aEid;
        chainIds[1] = bEid;
        chainIds[2] = cEid;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1.1 * 10**18;
        amounts[1] = 2 * 10**18;
        amounts[2] = 0.1 * 10**18;

        bool[] memory autogas = new bool[](3);
        autogas[0] = true;
        autogas[1] = false;
        autogas[2] = true;
        
        nftContract.setHigherBulkLimits(tokenId, address(user), chainIds, amounts, autogas);
        vm.stopPrank();
        console.log("set higher limits");
        console.log(nftContract.getWalletChainLimit(tokenId, address(user), aEid));
        console.log(nftContract.getWalletChainLimit(tokenId, address(user), bEid));
        console.log(nftContract.getWalletChainLimit(tokenId, address(user), cEid));

        autogas = nftContract.getAutogasConfig(tokenId, user);
        assertEq(autogas[1], false);

        amounts[0] = 0.42 * 10**18;
        amounts[1] = 0.69 * 10**18;
        amounts[2] = 0.2 * 10**18;

        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        vm.startPrank(issuer);
        bytes32 digest = keccak256(abi.encode(tokenId, user, chainIds, amounts, timestamp, uint256(0)));
        bytes32 hash = siggen.getEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, hash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();

        vm.startPrank(user);
        nftContract.setLowerBulkLimits(tokenId, user, chainIds, amounts, timestamp, 0, signature);
        console.log("set lower limits at", timestamp);
        console.log(nftContract.getWalletChainLimit(tokenId, address(user), aEid));
        console.log(nftContract.getWalletChainLimit(tokenId, address(user), bEid));
        console.log(nftContract.getWalletChainLimit(tokenId, address(user), cEid));
        vm.stopPrank();

        vm.warp(1720963281);
        timestamp = vm.getBlockTimestamp();
        uint256 newlimit = 0.1 * 10**18;
        vm.startPrank(issuer);
        digest = keccak256(abi.encodePacked(tokenId, user, uint256(3), newlimit, timestamp, uint256(1)));
        hash = siggen.getEthSignedMessageHash(digest);
        (v, r, s) = vm.sign(issuerPk, hash);
        signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();

        vm.startPrank(user);
        nftContract.setLowerLimit(tokenId, user, 3, newlimit, timestamp, 1, signature);
        console.log("set lower limits at", timestamp);
        console.log(nftContract.getWalletChainLimit(tokenId, address(user), cEid));
        nftContract.addManager(tokenId, user2);
        vm.stopPrank();

        uint256[] memory newLimits = new uint256[](4);
        newLimits[0] = 0.42 * 10**18;
        newLimits[1] = 0.69 * 10**18;
        newLimits[2] = 0.2 * 10**18;
        newLimits[3] = 2 * 10**18;

        uint256[] memory chainIds2 = new uint256[](4);
        chainIds2[0] = aEid;
        chainIds2[1] = bEid;
        chainIds2[2] = cEid;
        chainIds2[3] = dEid;


        vm.startPrank(issuer);
        digest = keccak256(abi.encodePacked(tokenId, user, timestamp, uint256(2)));
        hash = siggen.getEthSignedMessageHash(digest);
        (v, r, s) = vm.sign(issuerPk, hash);
        signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();


        vm.startPrank(user2);
        nftContract.resetWalletChainLimits(tokenId, address(user), timestamp, 2, signature);
        vm.stopPrank();
    }

    function testDisapproveChain() public {

    }

    function testMaxMint() public {
        vm.startPrank(userB);
        tokenId = nftContract.mint{value:0.02*1e18}();
        tokenId = nftContract.mint{value:0.02*1e18}();
        tokenId = nftContract.mint{value:0.02*1e18}();
        tokenId = nftContract.mint{value:0.02*1e18}();
        tokenId = nftContract.mint{value:0.02*1e18}();
        tokenId = nftContract.mint{value:0.02*1e18}();
        tokenId = nftContract.mint{value:0.02*1e18}();
        tokenId = nftContract.mint{value:0.02*1e18}();
        tokenId = nftContract.mint{value:0.02*1e18}();
        tokenId = nftContract.mint{value:0.02*1e18}();
        vm.expectRevert();
        tokenId = nftContract.mint{value:0.02*1e18}();
        vm.stopPrank();
        vm.prank(issuer);
        nftContract.setMaxNFTs(11);
        vm.startPrank(userB);
        tokenId = nftContract.mint{value:0.02*1e18}();
        vm.stopPrank();
        assertEq(tokenId,12);
    }

    function testMinting() public {
        vm.startPrank(userB);
        tokenId = nftContract.mint{value:0.02*1e18}();
        vm.stopPrank();
    }

    function testBalanceWithdrawal() public {
        vm.startPrank(userB);
        tokenId = nftContract.mint{value:0.02*1e18}();
        vm.stopPrank();
        vm.prank(issuer);
        nftContract.withdrawFunds();
    }

}