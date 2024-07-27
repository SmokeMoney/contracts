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

    uint16 SEND = 1;
    uint16 SEND_ABA = 2;

    string public _a = "A";
    string public _b = "B";

    address public user = address(0x1);
    address public userB = address(0x2);
    uint256 public initialBalance = 100 ether;

    AdminDepositContract public depositLocal;
    AdminDepositContract public depositCross;
    CoreNFTContract public nftContract;
    OperationsContract public accountOps;
    SignatureGenerator public siggen;
    WETH public weth;
    address public issuer;
    address public user2;
    uint256 internal issuerPk;
    uint256 tokenId;


    function setUp() public virtual override {
        (issuer, issuerPk) = makeAddrAndKey("issuer");


        vm.deal(userB, 1000 ether);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // issuer = address(1);
        user2 = address(3);
        
        
        nftContract = new CoreNFTContract("AutoGas", "OG", issuer, address(this), 0.02 * 1e18, 10);
        
        accountOps = OperationsContract(
            payable(_deployOApp(type(OperationsContract).creationCode, abi.encode(address(nftContract), address(endpoints[aEid]), address(0), address(issuer), address(this), 1)))
        );

        depositLocal = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(issuer), address(accountOps), address(0), address(0), address(0), 1, aEid, address(endpoints[aEid]), address(this))))
        );

        depositCross = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(issuer), address(accountOps), address(0), address(0), address(0), 1, bEid, address(endpoints[bEid]), address(this))))
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
        vm.stopPrank();
        
        accountOps.setDepositContract(aEid, address(depositLocal)); // Adding the deposit contract on the local chain
        accountOps.setDepositContract(bEid, address(depositCross)); // Adding the deposit contract on a diff chain


        assertEq(accountOps.adminChainId(), aEid);

        // The user is getting some WETH
        vm.deal(user, 100 ether);
        vm.deal(issuer, 100 ether);
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

    // Add more test cases here, for example:
    function testWithdrawOnChain() public {

        uint timestamp = vm.unixTime();

        vm.startPrank(issuer);
        bytes32 digest = keccak256(abi.encodePacked(user, address(weth), tokenId, uint256(0.1 * 10**18), uint32(aEid), timestamp, uint256(1)));
        bytes32 hash = siggen.getEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, hash);  
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.
        vm.stopPrank();     

        bytes memory options = new bytes(0);
        vm.startPrank(user);
        accountOps.withdraw(address(weth), tokenId, 0.1 * 10**18, aEid, timestamp, 1, signature, options, address(user));
        vm.stopPrank();
        assertEq(depositLocal.getDepositAmount(address(weth), tokenId), 0.9 * 10**18);
    }

            // Add more test cases here, for example:
    function testWithdrawCrossChain() public {

        EnforcedOptionParam[] memory aEnforcedOptions = new EnforcedOptionParam[](1);
        // Send gas for lzReceive (A -> B).
        aEnforcedOptions[0] = EnforcedOptionParam({eid: bEid, msgType: SEND, options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(90000, 0)}); // gas limit, msg.value
        // Send gas for lzReceive + msg.value for nested lzSend (A -> B -> A).        
        
        accountOps.setEnforcedOptions(aEnforcedOptions);

        uint timestamp = vm.unixTime();

        vm.startPrank(issuer);
        bytes32 digest = keccak256(abi.encodePacked(user, address(weth), tokenId, uint256(0.1 * 10**18), uint32(bEid), timestamp, uint256(1)));
        bytes memory signature = getIssuersSig(digest);  // note the order here is different from line above.
        vm.stopPrank();

        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(90000, 0); // gas settings for B -> A

        bytes memory payload = abi.encode(
            address(user),
            address(weth),
            tokenId,
            0.1 * 10**18,
            accountOps.getWithdrawNonce(tokenId)
        );

        MessagingFee memory sendFee = accountOps.quote(bEid, SEND, payload, extraOptions, false);
        vm.startPrank(user);
        accountOps.withdraw{value: sendFee.nativeFee}(address(weth), tokenId, 0.1 * 10**18, bEid, timestamp, 1, signature, extraOptions, address(user));
        vm.stopPrank();
        verifyPackets(bEid, addressToBytes32(address(depositCross)));

        assertEq(depositCross.getDepositAmount(address(weth), tokenId), 0.9 * 10**18);


        timestamp = vm.unixTime();

        vm.startPrank(issuer);
        digest = keccak256(abi.encodePacked(user, address(weth), tokenId, uint256(0.1 * 10**18), uint32(bEid), timestamp, uint256(2)));
        signature = getIssuersSig(digest);  // note the order here is different from line above.
        vm.stopPrank();

        payload = abi.encode(
            address(user),
            address(weth),
            tokenId,
            0.1 * 10**18,
            accountOps.getWithdrawNonce(tokenId)
        );

        sendFee = accountOps.quote(bEid, SEND, payload, extraOptions, false);
        vm.startPrank(user);
        accountOps.withdraw{value: sendFee.nativeFee}(address(weth), tokenId, 0.1 * 10**18, bEid, timestamp, 2, signature, extraOptions, address(user));
        vm.stopPrank();
        verifyPackets(bEid, addressToBytes32(address(depositCross)));

        assertEq(depositCross.getDepositAmount(address(weth), tokenId), 0.8 * 10**18);
    }

    function getIssuersSig(bytes32 digest) private view returns (bytes memory signature) {
        bytes32 hash = siggen.getEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, hash);
        signature = abi.encodePacked(r, s, v);
    }
}