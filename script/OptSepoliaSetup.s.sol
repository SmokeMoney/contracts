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
    uint32 ARBEID = 40231;
    uint32 ETHEID = 40161;
    uint32 OPTEID = 40232;
    uint32 BASEID = 40245;

    SmokeSpendingContract spendingContract;
    SmokeDepositContract depositContract;

    address owner = 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140;
    address issuer1 = 0xE0D6f93151091f24EA09474e9271BD60F2624d99;
    address lz_endpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    address issuer1NftContractAddress = 0x3e19BBEe16243F36b331Ce550f3fF2685e972944;
    address opsContractAddress = 0x3d4CF5232061744CA5E72eAB6624C96750D71EC2;
    
    address deposit_BAS_Address = 0x344DD3EF825c54f836C312CaC66294Fd2ce9F96c;
    address deposit_ARB_Address = 0xD5cE1f4A923B90dc9556bC17fBB65781cd71f5aE;
    address deposit_OPT_Address = 0xc6bA506F9E029104896F5B739487b67d4D19c1AD;
    address deposit_ETH_Address = 0x88d9872bB7eBA71254faE14E456C095DC1c5C1fA;
    address deposit_ZORA_Address = 0x74f96Ed7d11e9028352F44345F4A1D35bDF7d0E4;
    address deposit_BLAST_Address = 0xF4D2D99b401859c7b825D145Ca76125455154245;

    address payable spending_BAS_Address = payable(0x67077b70711026CE9d7C3f591D45924264a0c65b);
    address payable spending_ARB_Address = payable(0xACdB62538dB30EF5F9Cdb4F7E0640f856708449d);
    address payable spending_OPT_Address = payable(0xa1971bF0cEa6A6Fe47447914b0AB20118CF7B845);
    address payable spending_ETH_Address = payable(0x78DdB60EbD01D547164F4057C3d36948A66106b6);
    address payable spending_ZORA_Address = payable(0x73f0b82ea0C7268866Bb39E5a30f3f4E348E3FeB);
    address payable spending_BLAST_Address = payable(0x9b6f6F895a011c2C90857596A1AE2f537B097f52);

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
