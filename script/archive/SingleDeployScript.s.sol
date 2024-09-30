// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/src/Script.sol";
import "../../src/SmokeSpendingContract.sol";
import "../../src/AssemblePositionsContract.sol";
import "../../src/SmokeDepositContract.sol";
import "../../src/OperationsContract.sol";
import "../../src/CoreNFTContract.sol";
import "../../src/WstETHOracleReceiver.sol";

contract SetupScript is Script {
    uint32 ARBEID = 40231;
    uint32 ETHEID = 40161;
    uint32 OPTEID = 40232;
    uint32 BASEID = 40245;

    WstETHOracleReceiver wstETHOracle;
    AssemblePositionsContract assemblePositionsContract;
    OperationsContract accountOps;
    CoreNFTContract issuer1NftContract;
    SmokeSpendingContract spendingContract;
    SmokeDepositContract depositContract;

    address owner = 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140;
    address issuer1 = 0xE0D6f93151091f24EA09474e9271BD60F2624d99;
    address lz_endpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    address issuer1NftContractAddress;
    address opsCotnractAddress;

    address deposit_ARB_Address = 0xced5018D9C2d1088907581A7C24c670667F0079b;
    address deposit_ETH_Address = 0xB48F7a8aD1302C77C75acd3BB98f416000A99aad;
    address deposit_OPT_Address = 0x34e7CEBC535C30Aceeb63a63C20b0C42A80B215A;
    address deposit_BAS_Address;

    address payable spending_ARB_Address =
        payable(0x9F1b8D30D9e86B3bF65fa9f91722B4A3E9802382);
    address payable spending_ETH_Address =
        payable(0xC4e5BC86C3CAEd72dB41e62675f27b239Cb23bc6);
    address payable spending_OPT_Address =
        payable(0x4AA5F077688ba0d53836A3B9E9FDC3bFB16B1362);
    address payable spending_BAS_Address =
        payable(0xF1dE39102db79151F20cAC04D3A5DCe45a3D8Dbc);

    address weth_ARB_Address = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
    address weth_ETH_Address = 0xf531B8F309Be94191af87605CfBf600D71C2cFe0;
    address weth_OPT_Address = 0x74A4A85C611679B73F402B36c0F84A7D2CcdFDa3;
    address weth_BAS_Address = 0x4200000000000000000000000000000000000006;

    address wsteth_ARB_Address = 0xDF52714C191e8C4EC26cCD5B1578a904724e93b6;
    address wsteth_ETH_Address = 0x981830D1946e6FC9D5F893327a2819Fd5E2C5819;
    address wsteth_OPT_Address = 0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59;
    address wsteth_BAS_Address = 0x14440344256002a5afaA1403EbdAf4bf9a5499E3;

    function run() external {
        vm.startBroadcast();
        uint8 config = 3;
        if (config == 1) { // setting up all the contracts from scratch
            wstETHOracle = new WstETHOracleReceiver(
                0x4200000000000000000000000000000000000007, // L2 messenger
                0x0000000000000000000000000000000000000000 // l1 sender placehodler
            );
            console.log("wstETHOracle", address(wstETHOracle));

            assemblePositionsContract = new AssemblePositionsContract(
                address(wstETHOracle) // Oracle contract
            );
            console.log("assemblePositionsContract", address(assemblePositionsContract));

            accountOps = new OperationsContract(
                0x6EDCE65403992e310A62460808c4b910D972f10f, // LZ endpoint
                address(assemblePositionsContract),
                owner,
                BASEID // adminChainId
            );
            console.log("accountOps", address(accountOps));
            opsCotnractAddress = address(accountOps);
            issuer1NftContract = new CoreNFTContract(
                "Smoke Cards",
                "SMOKE",
                issuer1,
                0.02 * 1e18, // mint price
                10 // max nfts
            );
            console.log("issuer1NftContract", address(issuer1NftContract));
            issuer1NftContractAddress = address(issuer1NftContract);
            spendingContract = new SmokeSpendingContract(
                weth_BAS_Address,
                owner
            );
            console.log("spendingContract", address(spendingContract));
            depositContract = new SmokeDepositContract(
                address(accountOps),
                address(spendingContract),
                weth_BAS_Address,
                wsteth_BAS_Address,
                BASEID, // adminchain ID
                BASEID, // current chain ID
                lz_endpoint,
                owner
            );
            console.log("depositContract", address(depositContract));

            deposit_BAS_Address= address(depositContract);
            
            issuer1NftContract.approveChain(ARBEID);
            issuer1NftContract.approveChain(ETHEID);
            issuer1NftContract.approveChain(OPTEID);
            issuer1NftContract.approveChain(BASEID);

            spendingContract.addIssuer(
                address(issuer1NftContract),
                issuer1,
                1000, // borrow interest 10%
                1e15, // autogasThreshold 0.001 ETH
                1e15, // autogasRefill 0.001 ETH
                2 // gas price threshold
            );
        } else if (config==2){ // setting deposit addresses and wiring contracts
            accountOps = OperationsContract(opsCotnractAddress);

            accountOps.setDepositContract(ARBEID, deposit_ARB_Address); // Adding the deposit contract on the local chain
            accountOps.setDepositContract(ETHEID, deposit_ETH_Address); // Adding the deposit contract on a diff chain
            accountOps.setDepositContract(OPTEID, deposit_OPT_Address); // Adding the deposit contract on a diff chain
            accountOps.setDepositContract(BASEID, deposit_BAS_Address); // Adding the deposit contract on a diff chain

            accountOps.setPeer(ETHEID, addressToBytes32(deposit_ETH_Address));
            accountOps.setPeer(ARBEID, addressToBytes32(deposit_ARB_Address));
            accountOps.setPeer(OPTEID, addressToBytes32(deposit_OPT_Address));
        } else {
            spendingContract = SmokeSpendingContract(spending_BAS_Address);
            depositContract = SmokeDepositContract(deposit_BAS_Address);
            // spendingContract.poolDeposit{value: 0.5 * 1e18}(issuer1NftContractAddress);

            depositContract.addSupportedToken(weth_BAS_Address, issuer1NftContractAddress);
            depositContract.addSupportedToken(wsteth_BAS_Address, issuer1NftContractAddress);
        }
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
