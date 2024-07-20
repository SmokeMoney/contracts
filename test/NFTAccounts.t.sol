// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/deposit.sol";
import "../src/nftaccounts.sol";
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
    CrossChainLendingAccount public nftContract;
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
        
        nftContract = CrossChainLendingAccount(
            payable(_deployOApp(type(CrossChainLendingAccount).creationCode, abi.encode("AutoGas", "OG", address(issuer), address(endpoints[aEid]), address(this), uint256(aEid))))
        );

        depositLocal = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(issuer), address(nftContract), address(endpoints[aEid]), address(this))))
        );

        depositCross = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(issuer), address(nftContract), address(endpoints[bEid]), address(this))))
        );
        
        address[] memory oapps = new address[](2);
        oapps[0] = address(nftContract);
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
        nftContract.setDepositContract(aEid, address(depositLocal)); // Adding the deposit contract on the local chain
        nftContract.setDepositContract(bEid, address(depositCross)); // Adding the deposit contract on a diff chain
        vm.stopPrank();

        assertEq(nftContract.adminChainId(), aEid);

        vm.startPrank(user);
        uint256 amount = 10 ether;
        weth.deposit{value: amount}();
        weth.approve(address(depositLocal), 10 * 10**18);
        weth.approve(address(depositCross), 10 * 10**18);
        tokenId = nftContract.mint();
        depositLocal.deposit(address(weth), tokenId, 1 * 10**18);
        depositCross.deposit(address(weth), tokenId, 1 * 10**18);
        vm.stopPrank();
        assertEq(depositCross.getDepositAmount(address(weth), tokenId), 1 * 10**18);
    }

    function testAddWallets() public {

        vm.startPrank(user);
        nftContract.setHigherLimit(tokenId, address(user), aEid, 1 * 10**18);
        vm.stopPrank();


    }

    function testDisapproveChain() public {

    }

    function testManagerPowers() public {

    }

    function testMinting() public {
        vm.startPrank(userB);
        tokenId = nftContract.mint();
        vm.stopPrank();
    }

}