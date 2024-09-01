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

    address issuer1NftContractAddress = 0x6d5ecc0aa8DcE64045b1053A2480D82A61Ad86Bc;
    address opsCotnractAddress = 0x269488db82d434dC2E08e3B6f428BD1FF90C4325;
    
    address deposit_BAS_Address = 0x74Ee076c2ce51e081375B3f106e525646697809d;
    address deposit_ARB_Address = 0x873f2667Bd24982626a7e4A12d71491b89812e6b;
    address deposit_OPT_Address = 0x0F9F8AbFD3689A76916e7d19A8573F0899E0Da14;
    address deposit_ETH_Address = 0x2d5905509ee73e8abf0fd50988EE5cEd19b2ca90;

    address payable spending_BAS_Address = payable(0xa2926E337A8c0B366ba7c263F6EbBb018d306aF4);
    address payable spending_ARB_Address = payable(0xBFa2901F914A6a4f005D85181349F50a4981A776);
    address payable spending_OPT_Address = payable(0x6698928094A6Ac338eA71D66a9Bcdba028B81d4F);
    address payable spending_ETH_Address = payable(0x99741c2f93Df59e8c3D957998265b977e4b6CA72);

    address weth_ARB_Address = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
    address wsteth_ARB_Address = 0xDF52714C191e8C4EC26cCD5B1578a904724e93b6;

    function run() external {
        vm.startBroadcast();
        uint8 config = 3;
        if (config == 1) {
            // setting up all the contracts from scratch

            spendingContract = new SmokeSpendingContract(
                weth_ARB_Address,
                owner
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
            spendingContract = SmokeSpendingContract(spending_ARB_Address);
            depositContract = SmokeDepositContract(deposit_ARB_Address);
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
