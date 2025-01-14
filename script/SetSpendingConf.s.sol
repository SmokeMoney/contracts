// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/src/Script.sol";
import "../src/SmokeSpendingContract.sol";
import "../src/AssemblePositionsContract.sol";
import "../src/SmokeDepositContract.sol";
import "../src/OperationsContract.sol";
import "../src/CoreNFTContract.sol";
import "../src/WstETHOracleReceiver.sol";
import "../src/SpendingConfig.sol";

contract SetupScript is Script {
    uint32 ARBEID = 40231;
    uint32 ETHEID = 40161;
    uint32 OPTEID = 40232;
    uint32 BASEID = 40245;
    uint32 ZORA = 40287;
    uint32 BLASTID = 40243;

    SmokeSpendingContract spendingContract;
    SmokeDepositContract depositContract;
    SpendingConfig spendingConfContract;

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

    address weth_BLAST_Address = 0x4200000000000000000000000000000000000023;

    mapping(uint256 => address payable) public spendingAddresses;
    mapping(uint256 => address) public nftAddresses;
    mapping(uint256 => address payable) public borrowAndMintAddress;

    constructor() {
        setupAddresses();
    }

    function setupAddresses() internal {
        spendingAddresses[0] = payable(0x67077b70711026CE9d7C3f591D45924264a0c65b); // BASE
        spendingAddresses[1] = payable(0xACdB62538dB30EF5F9Cdb4F7E0640f856708449d); // ARB
        spendingAddresses[2] = payable(0xa1971bF0cEa6A6Fe47447914b0AB20118CF7B845); // OPT
        spendingAddresses[3] = payable(0x78DdB60EbD01D547164F4057C3d36948A66106b6); // ETH
        spendingAddresses[4] = payable(0x73f0b82ea0C7268866Bb39E5a30f3f4E348E3FeB); // ZORA
        spendingAddresses[5] = payable(0x9b6f6F895a011c2C90857596A1AE2f537B097f52); // BLAST

        nftAddresses[0] = 0xf5C17b101ad431d2eD9443360A5f6474C5471860; // BASE

        borrowAndMintAddress[0] = payable(0x95E1EE7D40E3A2BC275153De13ECAe75B358C4e1);
    }

    function run(uint8 chain) external {
        vm.startBroadcast();
        spendingConfContract = new SpendingConfig(owner, spendingAddresses[chain]);
        spendingContract = SmokeSpendingContract(spendingAddresses[chain]);
        spendingContract.setSpendingConfigContract(address(spendingConfContract));

        if (chain == 3) {
            spendingConfContract.setMaxRepayGas(5e15);
        } else {
            spendingConfContract.setMaxRepayGas(2e14);
        }
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
