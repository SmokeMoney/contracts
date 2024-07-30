// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/deposit.sol";
import "../src/corenft.sol";
import "../src/accountops.sol";
import "../src/lendingcontract.sol";
import "../src/weth.sol";
import "../src/siggen.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { MockPyth } from "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Wrapped stETH", "wstETH") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}


contract DepositTest is TestHelperOz5 {
    using ECDSA for bytes32;
    using OptionsBuilder for bytes;
    MockPyth public pyth;

    bytes32 ETH_PRICE_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 WSTETH_PRICE_FEED_ID = 0x6df640f3b8963d8f8358f791f352b8364513f6ab1cca5ed3f1f7b5448980e784;
    uint256 ETH_TO_WEI = 10 ** 18;


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
    uint256 public initialBalance = 100 ether;

    AdminDepositContract public depositLocal;
    AdminDepositContract public depositCrossB;
    AdminDepositContract public depositCrossC;
    AdminDepositContract public depositCrossD;
    CoreNFTContract public nftContract;
    OperationsContract public accountOps;
    CrossChainLendingContract public lendingcontract;
    CrossChainLendingContract public lendingcontractB;
    CrossChainLendingContract public lendingcontractD;
    CrossChainLendingContract public lendingcontractC;
    SignatureGenerator public siggen;
    WETH public weth;   
    MockERC20 public wstETH;
    address public issuer;
    address public user2;
    uint256 internal issuerPk;
    uint256 public adminChainIdReal;
    uint256 tokenId;


    function setUp() public virtual override {
        (issuer, issuerPk) = makeAddrAndKey("issuer");
        pyth = new MockPyth(60, 1);


        vm.deal(user2, 1000 ether);
        vm.deal(user, 100 ether);
        vm.deal(userB, 100 ether);
        vm.deal(issuer, 100 ether);

        super.setUp();
        setUpEndpoints(4, LibraryType.UltraLightNode);

        // issuer = address(1);
        user2 = address(3);
        adminChainIdReal = 1;
        
        vm.startPrank(issuer);
        wstETH = new MockERC20();
        wstETH.transfer(user, 1000 * 10**18);
        weth = new WETH();
        vm.stopPrank();

        nftContract = new CoreNFTContract("AutoGas", "OG", issuer, address(this), 0.02 * 1e18, 10);
        console.log(address(this));
        lendingcontract = new CrossChainLendingContract(issuer, address(weth), uint256(aEid));
        lendingcontractB = new CrossChainLendingContract(issuer, address(weth), uint256(bEid));
        lendingcontractC = new CrossChainLendingContract(issuer, address(weth), uint256(cEid));
        lendingcontractD = new CrossChainLendingContract(issuer, address(weth), uint256(dEid));

        accountOps = OperationsContract(
            payable(_deployOApp(type(OperationsContract).creationCode, abi.encode(address(nftContract), address(endpoints[aEid]), address(pyth), address(issuer), address(this), 1)))
        );

        depositLocal = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(accountOps), address(lendingcontract), address(weth), address(wstETH), 1, aEid, address(endpoints[aEid]), address(issuer), address(this))))
        );

        depositCrossB = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(0), address(lendingcontractB), address(weth), address(wstETH), 1, bEid, address(endpoints[bEid]), address(issuer), address(this))))
        );

        depositCrossC = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(0), address(lendingcontractC), address(weth), address(wstETH), 1, cEid, address(endpoints[cEid]), address(issuer), address(this))))
        );

        depositCrossD = AdminDepositContract(
            payable(_deployOApp(type(AdminDepositContract).creationCode, abi.encode(address(0), address(lendingcontractD), address(weth), address(wstETH), 1, dEid, address(endpoints[dEid]), address(issuer), address(this))))
        );


        // console.log("Set up all the contracts, ny: ", issuer);
        // console.log("Set up all the contracts, ny: ", address(this));
        address[] memory oapps = new address[](2);
        oapps[0] = address(accountOps);
        oapps[1] = address(depositCrossB);
        this.wireOApps(oapps);
        oapps[1] = address(depositCrossC);
        this.wireOApps(oapps);
        oapps[1] = address(depositCrossD);
        this.wireOApps(oapps);

        console.log(address(0));
        console.logBytes32(addressToBytes32(0xF4D2D99b401859c7b825D145Ca76125455154245));

        vm.startPrank(issuer);
        
        wstETH.transfer(user, 1000 * 10**18);
        siggen = new SignatureGenerator();
        depositCrossB.addSupportedToken(address(weth));
        depositCrossC.addSupportedToken(address(weth));
        depositCrossD.addSupportedToken(address(weth));
        depositCrossD.addSupportedToken(address(wstETH));
        depositLocal.addSupportedToken(address(weth));

        uint256 poolDepositAmount = 20 ether;
        lendingcontract.poolDeposit{value: poolDepositAmount}(poolDepositAmount);
        lendingcontractB.poolDeposit{value: poolDepositAmount}(poolDepositAmount);
        lendingcontractC.poolDeposit{value: poolDepositAmount}(poolDepositAmount);
        lendingcontractD.poolDeposit{value: poolDepositAmount}(poolDepositAmount);

        nftContract.approveChain(aEid); // Adding a supported chain
        nftContract.approveChain(bEid); // Adding a supported chain
        nftContract.approveChain(cEid); // Adding a supported chain
        nftContract.approveChain(dEid); // Adding a supported chain

        accountOps.setDepositContract(aEid, address(depositLocal)); // Adding the deposit contract on the local chain
        accountOps.setDepositContract(bEid, address(depositCrossB)); // Adding the deposit contract on a diff chain
        accountOps.setDepositContract(cEid, address(depositCrossC)); // Adding the deposit contract on a diff chain
        accountOps.setDepositContract(dEid, address(depositCrossD)); // Adding the deposit contract on a diff chain
        vm.stopPrank();

        assertEq(accountOps.adminChainId(), aEid);

        // The user is getting some WETH
        vm.startPrank(issuer);

        vm.stopPrank();
        vm.startPrank(user);

        tokenId = nftContract.mint{value:0.02*1e18}();
        uint256 amount = 10 ether;
        weth.deposit{value: amount}();
        weth.approve(address(depositLocal), 10 * 10**18);
        weth.approve(address(depositCrossB), 10 * 10**18);
        wstETH.approve(address(depositCrossD), 10 * 10**18);

        depositLocal.deposit(address(weth), tokenId, 1 * 10**18);
        depositCrossB.deposit(address(weth), tokenId, 1 * 10**18);
        depositCrossD.deposit(address(wstETH), tokenId, 1 * 10**18);


        uint256[] memory chainIds = new uint256[](4);
        chainIds[0] = aEid;
        chainIds[1] = bEid;
        chainIds[2] = cEid;
        chainIds[3] = dEid;

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1.1 * 10**18;
        amounts[1] = 3 * 10**18;
        amounts[2] = 0.2 * 10**18;
        amounts[3] = 0 * 10**18;

        bool[] memory autogas = new bool[](4);
        autogas[0] = true;
        autogas[1] = false;
        autogas[2] = true;
        autogas[3] = true;
        
        nftContract.setHigherBulkLimits(tokenId, address(user), chainIds, amounts, autogas);
        amounts[0] = 0 * 10**18;
        amounts[1] = 3 * 10**18;
        amounts[2] = 10 * 10**18;
        amounts[3] = 0.3 * 10**18;
        nftContract.setHigherBulkLimits(tokenId, address(user2), chainIds, amounts, autogas);

        console.log("Amoutn deposited, limits set");
        vm.stopPrank();
        
        assertEq(depositCrossB.getDepositAmount(address(weth), tokenId), 1 * 10**18);


        vm.warp(1720962281);
        uint256 timestamp = vm.getBlockTimestamp();
        bytes32 digest = keccak256(abi.encodePacked(user2, tokenId, uint256(2.8 * 10**18), timestamp, uint256(0), uint256(bEid)));
        bytes memory signature = getIssuersSig(digest); // note the order here is different from line above.

        vm.startPrank(user2);
        lendingcontractB.borrow(tokenId, uint256(2.8 * 10**18), timestamp, uint256(0), signature);
        vm.stopPrank();

        vm.warp(1720963281);
        timestamp = vm.getBlockTimestamp();
        digest = keccak256(abi.encodePacked(user, tokenId, uint256(0.19 * 10**18), timestamp, uint256(0), uint256(cEid)));
        signature = getIssuersSig(digest); 

        vm.startPrank(user);
        lendingcontractC.borrow(tokenId, uint256(0.19 * 10**18), timestamp, uint256(0), signature);
        vm.stopPrank();


        vm.warp(1720963381);
        console.log("User's borrow pos on chain 3: ", lendingcontractC.getBorrowPosition(tokenId, user));
        console.log("User's borrow pos on chain 2: ", lendingcontractB.getBorrowPosition(tokenId, user2));
        
    }

    function testOptimisticLiquidation() public {

        vm.warp(1720962281);
        vm.startPrank(issuer);
        weth.deposit{value:0.1 * 1e18}();
        weth.approve(address(depositCrossB), 0.1 * 1e18);
        depositCrossB.lockForLiquidation(address(weth), tokenId, 1e18);
        vm.warp(1721073281);
        depositCrossB.executeLiquidation(address(weth), tokenId, 1e18);
        vm.stopPrank();
        
    }

    function testLiquidationChallenge() public {

        vm.warp(1724984381);
        vm.startPrank(issuer);
        weth.deposit{value:1 * 1e18}();
        weth.approve(address(depositCrossB), 0.1 * 1e18);
        weth.approve(address(depositLocal), 0.1 * 1e18);
        depositCrossB.lockForLiquidation(address(weth), tokenId, 1e18);
        depositLocal.lockForLiquidation(address(weth), tokenId, 1e18);
        vm.stopPrank();

        vm.warp(1724985381);
        bytes[] memory updateData = createWstEthUpdate(4051);
        setEthPrice(3453);
        vm.startPrank(userB);
        uint256 assembleId = accountOps.createAssemblePositions{value: ETH_TO_WEI / 100}(tokenId, false, address(userB), updateData);
        vm.stopPrank();

        vm.startPrank(user);
        lendingcontractB.repay{value: 1e18}(tokenId, address(user2), address(user));
        vm.stopPrank();

        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0); // gas settings for B -> A


        address[] memory walletsReqChain = nftContract.getWalletsWithLimitChain(tokenId, bEid);
        bytes memory payload = getReportPositionsPayload(assembleId, tokenId, walletsReqChain);
        console.logBytes(new bytes(0));
        console.logBytes(payload);
        console.logBytes(extraOptions);

        // FIRST report
        MessagingFee memory sendFee = depositCrossB.quote(aEid, SEND, payload, extraOptions, false);

        vm.startPrank(user);
        vm.expectEmit();
        emit AdminDepositContract.PositionsReported(assembleId, tokenId);

        depositCrossB.reportPositions{value: sendFee.nativeFee}(assembleId, tokenId, walletsReqChain, extraOptions);
        vm.stopPrank();
        verifyPackets(aEid, addressToBytes32(address(accountOps)));

        // SECOND report
        sendFee = depositCrossC.quote(aEid, SEND, payload, extraOptions, false);

        vm.startPrank(user);
        depositCrossC.reportPositions{value: sendFee.nativeFee}(assembleId, tokenId, walletsReqChain, extraOptions);
        vm.stopPrank();
        verifyPackets(aEid, addressToBytes32(address(accountOps)));

        // THIRD report
        walletsReqChain = nftContract.getWalletsWithLimitChain(tokenId, dEid);
        payload = getReportPositionsPayload(assembleId, tokenId, walletsReqChain);
        sendFee = depositCrossD.quote(aEid, SEND, payload, extraOptions, false);

        vm.startPrank(user);
        depositCrossD.reportPositions{value: sendFee.nativeFee}(assembleId, tokenId, walletsReqChain, extraOptions);
        vm.stopPrank();
        verifyPackets(aEid, addressToBytes32(address(accountOps)));
        

        // Fourth report
        walletsReqChain = nftContract.getWalletsWithLimitChain(tokenId, aEid);
        accountOps.getOnChainReport(assembleId, tokenId, walletsReqChain, new bytes(0));
        payload = getReportPositionsPayload(assembleId, tokenId, walletsReqChain);
        
        assertEq(accountOps.getAssembleChainsReported(assembleId), 4);

        console.log(weth.balanceOf(issuer));
        vm.startPrank(userB);
        accountOps.liquidationChallenge(assembleId, address(weth), aEid, address(userB), new bytes(0));


        extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(70000, 0); // gas settings for B -> A

        payload = abi.encode(
            address(0),
            address(0),
            tokenId,
            assembleId, // random uint256, just for calculations
            assembleId, // random uint256, just for calculations
            assembleId
        );

        sendFee = accountOps.quote(bEid, SEND, accountOps.encodeMessage(2, payload), extraOptions, false);

        accountOps.liquidationChallenge{value: sendFee.nativeFee}(assembleId, address(weth), bEid, address(userB), extraOptions);

        verifyPackets(bEid, addressToBytes32(address(depositCrossB)));
        vm.stopPrank();
        console.log(weth.balanceOf(issuer));

        assertEq(depositLocal.isLiquidationLocked(address(weth), tokenId), false);
        assertEq(depositCrossB.isLiquidationLocked(address(weth), tokenId), false);

    }

    function getIssuersSig(bytes32 digest) private view returns (bytes memory signature) {
        bytes32 hash = siggen.getEthSignedMessageHash(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(issuerPk, hash);
        signature = abi.encodePacked(r, s, v);
    }

    function getReportPositionsPayload(uint256 tokenId2, uint256 assembleId, address[] memory walletsReqChain) private pure returns ( bytes memory payload ){
        uint256 depositAmount = 0;
        uint256 wstETHDepositAmount = 0;
        address wethAddress = address(0);
        address wstETHAddress = address(0);
        uint256[] memory borrowAmounts = new uint256[](walletsReqChain.length);
        uint256[] memory interestAmounts = new uint256[](walletsReqChain.length);

        payload = abi.encode(
            assembleId, 
            tokenId2, 
            depositAmount, 
            wstETHDepositAmount, 
            wethAddress, 
            wstETHAddress,
            depositAmount,
            walletsReqChain,
            borrowAmounts,
            interestAmounts
        );
    }


    function createEthUpdate(int64 ethPrice) private view returns (bytes[] memory) {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = pyth.createPriceFeedUpdateData(
            ETH_PRICE_FEED_ID,
            ethPrice * 100000,
            10 * 100000,
            -5,
            ethPrice * 100000,
            10 * 100000,
            uint64(block.timestamp),
            uint64(block.timestamp)
        );
        
        return updateData;
    }

    function createWstEthUpdate(int64 wstETHPrice) private view returns (bytes[] memory) {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = pyth.createPriceFeedUpdateData(
            WSTETH_PRICE_FEED_ID,
            wstETHPrice * 100000,
            10 * 100000,
            -5,
            wstETHPrice * 100000,
            10 * 100000,
            uint64(block.timestamp),
            uint64(block.timestamp)
        );
        
        return updateData;
    }


    function setEthPrice(int64 ethPrice) private {
        bytes[] memory updateData = createEthUpdate(ethPrice);
        uint value = pyth.getUpdateFee(updateData);
        vm.deal(address(this), value);
        pyth.updatePriceFeeds{ value: value }(updateData);
    }

}