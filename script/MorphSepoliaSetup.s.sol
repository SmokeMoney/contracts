// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/src/Script.sol";
import "../src/SmokeSpendingContract.sol";
import "../src/AssemblePositionsContract.sol";
import "../src/SmokeDepositContract.sol";
import "../src/OperationsContract.sol";
import "../src/CoreNFTContract.sol";
import "../src/WstETHOracleReceiver.sol";

contract SetupScript is Script {
    uint32 BASEID = 40245;
    uint32 MORPHID = 40290;

    SmokeSpendingContract spendingContract;
    SmokeDepositContract depositContract;

    address owner = 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140;
    address issuer1 = 0xE0D6f93151091f24EA09474e9271BD60F2624d99;
    address lz_endpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    address issuer1NftContractAddress = 0xA500C712e7EbDd5040f1A212800f5f6fa20d05F8;
    address opsContractAddress = 0x54764680B3863A1B72C376Ae92a3cCE65C4DdE69;
    
    address deposit_MORPH_Address = 0x2Cbe484B1E2fe4ffA28Fef0cAa0C9E0D724Fe183;

    address payable spending_MORPH_Address = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3);

    address weth_MORPH_Address = 0x5300000000000000000000000000000000000011;
    address wsteth_MORPH_Address = 0xcC3551B5B93733E31AF0c2C7ae4998908CBfB2A1;

    function run(uint8 config) external {
        vm.startBroadcast();
        if (config == 1) {
            // setting up all the contracts from scratch

            // spendingContract = new SmokeSpendingContract(
            //     weth_MORPH_Address,
            //     owner
            // );
            spendingContract = SmokeSpendingContract(spending_MORPH_Address);
            // console.log("spendingContract", address(spendingContract));
            
            // depositContract = new SmokeDepositContract(
            //     address(0),
            //     address(spendingContract),
            //     weth_MORPH_Address,
            //     wsteth_MORPH_Address,
            //     BASEID, // adminchain ID
            //     MORPHID, // current chain ID
            //     lz_endpoint,
            //     owner
            // );
            // console.log("depositContract", address(depositContract));

            spendingContract.addIssuer(
                issuer1NftContractAddress,
                issuer1,
                1000, // borrow interest 10%
                1e15, // autogasThreshold 0.001 ETH
                1e15, // autogasRefill 0.001 ETH
                2 // gas price threshold
            );

            depositContract.setPeer(
                BASEID, // adminchain ID
                addressToBytes32(opsContractAddress)
            );

        } else if (config == 3) {
            spendingContract = SmokeSpendingContract(spending_MORPH_Address);
            depositContract = SmokeDepositContract(deposit_MORPH_Address);
            spendingContract.poolDeposit{value: 0.005 * 1e18}(
                issuer1NftContractAddress
            );

            depositContract.addSupportedToken(
                weth_MORPH_Address,
                issuer1NftContractAddress
            );
        }
        else if (config == 7) {
            spendingContract = SmokeSpendingContract(spending_MORPH_Address);
            uint256 wethBalance = IWETH2(weth_MORPH_Address).balanceOf(address(spendingContract));
            spendingContract.poolWithdraw(wethBalance, issuer1NftContractAddress);
        }
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
