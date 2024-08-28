// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/SmokeSpendingContract.sol";
import "../src/AssemblePositionsContract.sol";
import "../src/SmokeDepositContract.sol";
import "../src/OperationsContract.sol";
import "../src/CoreNFTContract.sol";
import "../src/WstETHOracleReceiver.sol";

contract SetupScript is Script {
    uint32 ARBEID = 40231;
    uint32 ETHEID = 40161;
    uint32 OPTEID = 40232;
    uint32 BASEID = 40245;

    SmokeSpendingContract spendingContract;
    SmokeDepositContract depositContract;

    address owner = 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140;
    address issuer1 = 0xE0D6f93151091f24EA09474e9271BD60F2624d99;
    address lz_endpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    address issuer1NftContractAddress =
        0x34e7CEBC535C30Aceeb63a63C20b0C42A80B215A;
    address opsCotnractAddress = 0x4AA5F077688ba0d53836A3B9E9FDC3bFB16B1362;

    address depositAddress = 0xced5018D9C2d1088907581A7C24c670667F0079b;

    address payable spendingAddress =
        payable(0x9F1b8D30D9e86B3bF65fa9f91722B4A3E9802382);

    address weth_ARB_Address = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
    address wsteth_ARB_Address = 0xDF52714C191e8C4EC26cCD5B1578a904724e93b6;

    function run() external {
        vm.startBroadcast();
        uint8 config = 3;
        if (config == 1) {
            // setting up all the contracts from scratch

            spendingContract = new SmokeSpendingContract(
                weth_ARB_Address,
                owner,
                ARBEID // current chain ID (LZ)
            );
            console.log("spendingContract", address(spendingContract));

            depositContract = new SmokeDepositContract(
                address(0),
                address(spendingContract),
                weth_ARB_Address,
                wsteth_ARB_Address,
                ARBEID, // adminchain ID
                ARBEID, // current chain ID
                lz_endpoint,
                owner
            );
            console.log("depositContract", address(depositContract));

            spendingContract.addIssuer(
                issuer1NftContractAddress,
                issuer1,
                1000, // borrow interest 10%
                1e15, // autogasThreshold 0.001 ETH
                1e15, // autogasRefill 0.001 ETH
                2 // gas price threshold
            );

            depositContract.setPeer(
                ARBEID,
                addressToBytes32(opsCotnractAddress)
            );

        } else if (config == 3) {
            spendingContract = SmokeSpendingContract(spendingAddress);
            depositContract = SmokeDepositContract(depositAddress);
            spendingContract.poolDeposit{value: 0.5 * 1e18}(
                issuer1NftContractAddress
            );

            depositContract.addSupportedToken(
                weth_ARB_Address,
                issuer1NftContractAddress
            );
            depositContract.addSupportedToken(
                wsteth_ARB_Address,
                issuer1NftContractAddress
            );
        }
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
