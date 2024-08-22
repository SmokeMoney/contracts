// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/deposit.sol";
import "../src/corenft.sol";
import "../src/accountops.sol";
import "../src/borrow.sol";
import "../src/wstETHOracleReceiver.sol";


import "../src/archive/weth.sol";
import "../src/archive/siggen.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Wrapped stETH", "wstETH") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract CrossDomainMessenger {
    function xDomainMessageSender() external view returns (address) {
        return address(42);
    }
}

contract Setup is TestHelperOz5 {
    using ECDSA for bytes32;
    using OptionsBuilder for bytes;
    
    uint256 ETH_TO_WEI = 10 ** 18;


    uint32 aEid = 1;
    uint32 bEid = 2;
    uint32 cEid = 3;
    uint32 dEid = 4;

    string public _a = "A";
    string public _b = "B";

    address public user = address(0x1);
    address public userB = address(0x2);
    uint256 public initialBalance = 100 ether;

    AdminDepositContract public depositLocal;
    AdminDepositContract public depositCrossB;
    AdminDepositContract public depositCrossC;
    AdminDepositContract public depositCrossD;
    CoreNFTContract public issuer1NftContract;
    address public issuer1NftAddress;
    OperationsContract public accountOps;
    WstETHOracleReceiver public wstETHOracle;
    CrossDomainMessenger public l2_messenger;
    SmokeSpendingContract public lendingcontract;
    SmokeSpendingContract public lendingcontractB;
    SmokeSpendingContract public lendingcontractD;
    SmokeSpendingContract public lendingcontractC;
    SignatureGenerator public siggen;
    
    WETH public weth;   
    MockERC20 public wstETH;
    address public issuer1;
    address public user2;
    uint256 internal issuer1Pk;
    uint256 public adminChainIdReal;
    uint256 tokenId;


    function setUp() public virtual override{
        (issuer1, issuer1Pk) = makeAddrAndKey("issuer");

        vm.deal(user2, 1000 ether);
        vm.deal(user, 100 ether);
        vm.deal(userB, 100 ether);
        vm.deal(issuer1, 100 ether);

        super.setUp();
        setUpEndpoints(4, LibraryType.UltraLightNode);

        // issuer = address(1);
        user2 = address(3);
        adminChainIdReal = 1;
        
        vm.startPrank(issuer1);
        wstETH = new MockERC20();
        wstETH.transfer(user, 1000 * 10**18);
        weth = new WETH();
        vm.stopPrank();

        issuer1NftContract = new CoreNFTContract("AutoGas", "OG", issuer1, address(this), 0.02 * 1e18, 10);

        issuer1NftAddress = address(issuer1NftContract);
        
        lendingcontract = new SmokeSpendingContract(address(weth), uint256(aEid));
        lendingcontractB = new SmokeSpendingContract(address(weth), uint256(bEid));
        lendingcontractC = new SmokeSpendingContract(address(weth), uint256(cEid));
        lendingcontractD = new SmokeSpendingContract(address(weth), uint256(dEid));

        l2_messenger = new CrossDomainMessenger();
        wstETHOracle = new WstETHOracleReceiver(address(l2_messenger), address(42));

        vm.prank(address(l2_messenger));
        wstETHOracle.setWstETHRatio(1.17*1e18);

        accountOps = OperationsContract(
            payable(_deployOApp(type(OperationsContract).creationCode, abi.encode(address(issuer1NftContract), address(endpoints[aEid]), address(wstETHOracle), address(this), 1)))
        );

        depositLocal = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(accountOps), address(lendingcontract), address(weth), address(wstETH), 1, aEid, address(endpoints[aEid]), address(this))))
        );

        depositCrossB = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(0), address(lendingcontractB), address(weth), address(wstETH), 1, bEid, address(endpoints[bEid]), address(this))))
        );

        depositCrossC = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(0), address(lendingcontractC), address(weth), address(wstETH), 1, cEid, address(endpoints[cEid]), address(this))))
        );

        depositCrossD = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(0), address(lendingcontractD), address(weth), address(wstETH), 1, dEid, address(endpoints[dEid]), address(this))))
        );


        // console.log("Set up all the contracts, ny: ", issuer1);
        // console.log("Set up all the contracts, ny: ", address(this));
        address[] memory oapps = new address[](2);
        oapps[0] = address(accountOps);
        oapps[1] = address(depositCrossB);
        this.wireOApps(oapps);
        oapps[1] = address(depositCrossC);
        this.wireOApps(oapps);
        oapps[1] = address(depositCrossD);
        this.wireOApps(oapps);

        accountOps.addIssuer(issuer1NftAddress);
        lendingcontract.addIssuer(issuer1NftAddress, issuer1, 1000, 1e15, 1e15, 1e13, 2);
        lendingcontractB.addIssuer(issuer1NftAddress, issuer1, 1000, 1e15, 1e15, 1e13, 2);
        lendingcontractC.addIssuer(issuer1NftAddress, issuer1, 1000, 1e15, 1e15, 1e13, 2);
        lendingcontractD.addIssuer(issuer1NftAddress, issuer1, 1000, 1e15, 1e15, 1e13, 2);

        accountOps.setDepositContract(aEid, address(depositLocal)); // Adding the deposit contract on the local chain
        accountOps.setDepositContract(bEid, address(depositCrossB)); // Adding the deposit contract on a diff chain
        accountOps.setDepositContract(cEid, address(depositCrossC)); // Adding the deposit contract on a diff chain
        accountOps.setDepositContract(dEid, address(depositCrossD)); // Adding the deposit contract on a diff chain

        vm.startPrank(issuer1);
        
        wstETH.transfer(user, 1000 * 10**18);
        siggen = new SignatureGenerator();
        depositCrossB.addSupportedToken(address(weth), issuer1NftAddress);
        depositCrossC.addSupportedToken(address(weth), issuer1NftAddress);
        depositCrossD.addSupportedToken(address(weth), issuer1NftAddress);
        depositCrossD.addSupportedToken(address(wstETH), issuer1NftAddress);
        depositLocal.addSupportedToken(address(weth), issuer1NftAddress);

        uint256 poolDepositAmount = 20 ether;
        lendingcontract.poolDeposit{value: poolDepositAmount}(issuer1NftAddress);
        lendingcontractB.poolDeposit{value: poolDepositAmount}(issuer1NftAddress);
        lendingcontractC.poolDeposit{value: poolDepositAmount}(issuer1NftAddress);
        lendingcontractD.poolDeposit{value: poolDepositAmount}(issuer1NftAddress);

        issuer1NftContract.approveChain(aEid); // Adding a supported chain
        issuer1NftContract.approveChain(bEid); // Adding a supported chain
        issuer1NftContract.approveChain(cEid); // Adding a supported chain
        issuer1NftContract.approveChain(dEid); // Adding a supported chain
        vm.stopPrank();

        assertEq(accountOps.adminChainId(), aEid);

        // The user is getting some WETH
        vm.startPrank(user);

        tokenId = issuer1NftContract.mint{value:0.02*1e18}();
        uint256 amount = 10 ether;
        weth.deposit{value: amount}();
        weth.approve(address(depositLocal), 10 * 10**18);
        weth.approve(address(depositCrossB), 10 * 10**18);
        wstETH.approve(address(depositCrossD), 10 * 10**18);


        depositCrossB.depositETH{value: 1e18}(issuer1NftAddress, tokenId, 1e18);
        depositLocal.depositETH{value: 1e18}(issuer1NftAddress, tokenId, 1e18);
        depositLocal.deposit(issuer1NftAddress, address(weth), tokenId, 1 * 10**18);
        depositCrossD.deposit(issuer1NftAddress, address(wstETH), tokenId, 1 * 10**18);

    }

    function setupRateLimits() public virtual {


        uint256[] memory chainIds = new uint256[](4);
        chainIds[0] = aEid;
        chainIds[1] = bEid;
        chainIds[2] = cEid;
        chainIds[3] = dEid;

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1.1 * 10**18;
        amounts[1] = 2 * 10**18;
        amounts[2] = 0.1 * 10**18;
        amounts[3] = 0 * 10**18;

        bool[] memory autogas = new bool[](4);
        autogas[0] = true;
        autogas[1] = false;
        autogas[2] = true;
        autogas[3] = true;
        
        issuer1NftContract.setHigherBulkLimits(tokenId, addressToBytes32(address(user)), chainIds, amounts, autogas);
        amounts[0] = 0 * 10**18;
        amounts[1] = 2 * 10**18;
        amounts[2] = 10 * 10**18;
        amounts[3] = 0.3 * 10**18;
        issuer1NftContract.setHigherBulkLimits(tokenId, addressToBytes32(address(user2)), chainIds, amounts, autogas);

        console.log("Amoutn deposited, limits set");
        vm.stopPrank();
        
        assertEq(depositCrossB.getDepositAmount(issuer1NftAddress, tokenId, address(weth)), 1 * 10**18);

    }

    function superSetup() public virtual {

        super.setUp();
    }


}