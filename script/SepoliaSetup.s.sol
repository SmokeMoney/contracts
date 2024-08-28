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
        0x9C2e3e224F0f5BFaB7B3C454F0b4357d424EF030;
    address opsCotnractAddress = 0x981830D1946e6FC9D5F893327a2819Fd5E2C5819;

    address depositAddress = 0xB48F7a8aD1302C77C75acd3BB98f416000A99aad;

    address payable spendingAddress =
        payable(0xC4e5BC86C3CAEd72dB41e62675f27b239Cb23bc6);

    address weth_ETH_Address = 0xf531B8F309Be94191af87605CfBf600D71C2cFe0;
    address wsteth_ETH_Address = 0x981830D1946e6FC9D5F893327a2819Fd5E2C5819;

    function run() external {
        vm.startBroadcast();

        uint8 config = 3;
        if (config == 1) {
            // setting up all the contracts from scratch
            spendingContract = new SmokeSpendingContract(
                weth_ETH_Address,
                owner,
                ETHEID // current chain ID (LZ)
            );
            console.log("spendingContract", address(spendingContract));

            depositContract = new SmokeDepositContract(
                address(0),
                address(spendingContract),
                weth_ETH_Address,
                wsteth_ETH_Address,
                ETHEID, // adminchain ID
                ETHEID, // current chain ID
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
                ETHEID,
                addressToBytes32(opsCotnractAddress)
            );
        } else if (config == 3) {
            spendingContract = SmokeSpendingContract(spendingAddress);
            depositContract = SmokeDepositContract(depositAddress);
            depositContract.addSupportedToken(
                weth_ETH_Address,
                issuer1NftContractAddress
            );
            depositContract.addSupportedToken(
                wsteth_ETH_Address,
                issuer1NftContractAddress
            );
            spendingContract.poolDeposit{value: 0.5 * 1e18}(
                issuer1NftContractAddress
            );
        }
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
