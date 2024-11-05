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
    uint32 ZORAID = 40249;
    uint32 BLASTID = 40243;


    WstETHOracleReceiver wstETHOracle;
    AssemblePositionsContract assemblePositionsContract;
    OperationsContract accountOps;
    CoreNFTContract issuer1NftContractOld;
    CoreNFTContract issuer1NftContract;
    SmokeSpendingContract spendingContract;
    SmokeDepositContract depositContract;

    address owner = 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140;
    address issuer1 = 0xE0D6f93151091f24EA09474e9271BD60F2624d99;
    address lz_endpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    address issuer1NftContractAddressOld = 0xA500C712e7EbDd5040f1A212800f5f6fa20d05F8;
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
    
    address weth_ARB_Address = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
    address weth_ETH_Address = 0xf531B8F309Be94191af87605CfBf600D71C2cFe0;
    address weth_OPT_Address = 0x74A4A85C611679B73F402B36c0F84A7D2CcdFDa3;
    address weth_BAS_Address = 0x4200000000000000000000000000000000000006;
    address weth_SCROLL_Address = 0x5300000000000000000000000000000000000004;

    address wsteth_ARB_Address = 0xDF52714C191e8C4EC26cCD5B1578a904724e93b6;
    address wsteth_ETH_Address = 0x981830D1946e6FC9D5F893327a2819Fd5E2C5819;
    address wsteth_OPT_Address = 0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59;
    address wsteth_BAS_Address = 0x14440344256002a5afaA1403EbdAf4bf9a5499E3;
    address wsteth_SCROLL_Address = 0x14440344256002a5afaA1403EbdAf4bf9a5499E3;

    function run(uint8 config) external {
        vm.startBroadcast();
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

            issuer1NftContract = new CoreNFTContract(
                "Smoke OG",
                "OG",
                issuer1,
                0.02 * 1e18, // mint price
                10 // max nfts
            );
            console.log("issuer1NftContract", address(issuer1NftContract));

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

            spendingContract.addIssuer(
                address(issuer1NftContract),
                issuer1,
                1000, // borrow interest 10%
                1e15, // autogasThreshold 0.001 ETH
                1e15, // autogasRefill 0.001 ETH
                2 // gas price threshold
            );
        } else if (config==2){ // setting deposit addresses and wiring contracts
            accountOps = OperationsContract(opsContractAddress);

            accountOps.setDepositContract(ARBEID, deposit_ARB_Address); // Adding the deposit contract on the local chain
            accountOps.setDepositContract(ETHEID, deposit_ETH_Address); // Adding the deposit contract on a diff chain
            accountOps.setDepositContract(OPTEID, deposit_OPT_Address); // Adding the deposit contract on a diff chain
            accountOps.setDepositContract(BASEID, deposit_BAS_Address); // Adding the deposit contract on a diff chain
            accountOps.setDepositContract(ZORAID, deposit_BAS_Address); // Adding the deposit contract on a diff chain

            accountOps.setPeer(ETHEID, addressToBytes32(deposit_ETH_Address));
            accountOps.setPeer(ARBEID, addressToBytes32(deposit_ARB_Address));
            accountOps.setPeer(OPTEID, addressToBytes32(deposit_OPT_Address));
            accountOps.setPeer(ZORAID, addressToBytes32(deposit_ZORA_Address));
        } else if (config ==3) {

            spendingContract = SmokeSpendingContract(spending_BAS_Address);
            depositContract = SmokeDepositContract(deposit_BAS_Address);
            issuer1NftContract = CoreNFTContract(issuer1NftContractAddress);
            spendingContract.poolDeposit{value: 0.5 * 1e18}(issuer1NftContractAddress);

            issuer1NftContract.approveChain(ARBEID);
            issuer1NftContract.approveChain(ETHEID);
            issuer1NftContract.approveChain(OPTEID);
            issuer1NftContract.approveChain(BASEID);
            issuer1NftContract.approveChain(ZORAID);

            issuer1NftContract.setDefaultNativeCredit(10000000000000000);

            depositContract.addSupportedToken(weth_BAS_Address, issuer1NftContractAddress);
            depositContract.addSupportedToken(wsteth_BAS_Address, issuer1NftContractAddress);
        }
        else if (config ==4) { // add new chian
            accountOps = OperationsContract(opsContractAddress);

            accountOps.setDepositContract(BLASTID, deposit_BLAST_Address); // Adding the deposit contract on the local chain
            accountOps.setPeer(BLASTID, addressToBytes32(deposit_BLAST_Address));
        }
        else if (config == 5){ // with issuer address
            issuer1NftContract = CoreNFTContract(issuer1NftContractAddress);
            issuer1NftContract.approveChain(BLASTID);
        }
        else if (config == 7) {
            spendingContract = SmokeSpendingContract(spending_BAS_Address);
            uint256 wethBalance = IWETH2(weth_BAS_Address).balanceOf(address(spendingContract));
            spendingContract.poolWithdraw(wethBalance, issuer1NftContractAddress);
        }
        else if (config == 8) {
            issuer1NftContractOld = CoreNFTContract(issuer1NftContractAddressOld);
            issuer1NftContract = CoreNFTContract(issuer1NftContractAddress);
            uint256[] memory chainList = issuer1NftContractOld.getChainList();
            uint256 totalSupply = issuer1NftContractOld.totalSupply();
            for (uint256 i=10; i<totalSupply;i++){
                uint256 nftId = i+1;
                console.log(nftId, issuer1NftContractOld.ownerOf(nftId));
                uint256 newNftId = issuer1NftContract.mint{value: 0.02 * 1e18}(0);
                console.log(newNftId);
                bytes32[] memory wallets = issuer1NftContractOld.getWallets(nftId);
                for (uint256 j=0; j<wallets.length; j++){
                    uint256[] memory limitsConfig = issuer1NftContractOld.getLimitsConfig(nftId, wallets[j]);
                    bool[] memory autogasConfig = issuer1NftContractOld.getAutogasConfig(nftId, wallets[j]);
                    issuer1NftContract.setHigherBulkLimits(
                        newNftId,
                        wallets[j],
                        chainList,
                        limitsConfig,
                        autogasConfig
                    );
                }
                issuer1NftContract.safeTransferFrom(issuer1, issuer1NftContractOld.ownerOf(nftId), newNftId);
            }
        }
        else if (config == 9) {
            issuer1NftContractOld = CoreNFTContract(issuer1NftContractAddressOld);
            uint256 nftId = 34;
            bytes32[] memory wallets = issuer1NftContractOld.getWallets(nftId);
            for (uint256 j=0; j<wallets.length; j++){
                uint256[] memory limitsConfig = issuer1NftContractOld.getLimitsConfig(nftId, wallets[j]);
                bool[] memory autogasConfig = issuer1NftContractOld.getAutogasConfig(nftId, wallets[j]);
                for (uint256 k=0;k<limitsConfig.length; k++) {
                    console.log(limitsConfig[k]);
                    console.log(autogasConfig[k]);
                }
            }
        }
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
