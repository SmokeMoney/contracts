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

    address issuer1NftContractAddress = 0xA500C712e7EbDd5040f1A212800f5f6fa20d05F8;
    address opsContractAddress = 0x54764680B3863A1B72C376Ae92a3cCE65C4DdE69;

    address deposit_BAS_Address = 0x617324745740d7CE92e0E1AB325870F186bDC1a1;
    address deposit_ARB_Address = 0x3e19BBEe16243F36b331Ce550f3fF2685e972944;
    address deposit_OPT_Address = 0x73A257e356Dd6Eb65c2cE9753C67f43Ae3e33A6B;
    address deposit_ETH_Address = 0xdaab75CA8E7E3c0F880C4D1727c9c287139b2CA5;
    address deposit_ZORA_Address = 0x2Cbe484B1E2fe4ffA28Fef0cAa0C9E0D724Fe183;
    
    address payable spending_BAS_Address = payable(0xdaab75CA8E7E3c0F880C4D1727c9c287139b2CA5);
    address payable spending_ARB_Address = payable(0x3d4CF5232061744CA5E72eAB6624C96750D71EC2);
    address payable spending_OPT_Address = payable(0xBfE686A5BD487B52943D9E550e42C4910aB33888);
    address payable spending_ETH_Address = payable(0xA500C712e7EbDd5040f1A212800f5f6fa20d05F8);
    address payable spending_ZORA_Address = payable(0xDF52714C191e8C4EC26cCD5B1578a904724e93b6);

    address weth_OPT_Address = 0x74A4A85C611679B73F402B36c0F84A7D2CcdFDa3;
    address wsteth_OPT_Address = 0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59;

    function run(uint8 config) external {
        vm.startBroadcast();

        if (config == 1) {
            // setting up all the contracts from scratch
            spendingContract = new SmokeSpendingContract(
                weth_OPT_Address,
                owner
            );
            console.log("spendingContract", address(spendingContract));

            depositContract = new SmokeDepositContract(
                address(0),
                address(spendingContract),
                weth_OPT_Address,
                wsteth_OPT_Address,
                BASEID, // adminchain ID
                OPTEID, // current chain ID
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
                BASEID, // adminchain ID
                addressToBytes32(opsContractAddress)
            );
        } else if (config == 3) {
            spendingContract = SmokeSpendingContract(spending_OPT_Address);
            depositContract = SmokeDepositContract(deposit_OPT_Address);
            depositContract.addSupportedToken(
                weth_OPT_Address,
                issuer1NftContractAddress
            );
            depositContract.addSupportedToken(
                wsteth_OPT_Address,
                issuer1NftContractAddress
            );
            spendingContract.poolDeposit{value: 0.5 * 1e18}(
                issuer1NftContractAddress
            );
        }
        else if (config == 7) {
            spendingContract = SmokeSpendingContract(spending_OPT_Address);
            uint256 wethBalance = IWETH2(weth_OPT_Address).balanceOf(address(spendingContract));
            spendingContract.poolWithdraw(wethBalance, issuer1NftContractAddress);
        }

        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
