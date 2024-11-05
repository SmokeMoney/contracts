// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "../src/SmokeSpendingContract.sol";
import "../src/AssemblePositionsContract.sol";
import "../src/SmokeDepositContract.sol";
import "../src/OperationsContract.sol";
import "../src/CoreNFTContract.sol";
import "../src/WstETHOracleReceiver.sol";

contract SetupScript is Script {
    uint32 BASEID = 40245;
    uint32 ARBEID = 40231;
    uint32 OPTEID = 40232;
    uint32 ETHEID = 40161;
    uint32 ZORAID = 40249;
    uint32 BLASTID = 40243;
    uint32 SCROLLID = 40170;
    uint32 LINEAID = 40287;
    uint32 ZKSYNCID = 40305;
    uint32 ODYSSEYID = 40169; // FAKE ODYSSEY ID
    uint32 UNICHAINID = 40333;

    SmokeSpendingContract spendingContract;
    SmokeDepositContract depositContract;

    mapping(uint256 => uint32) public chainIds;
    mapping(uint256 => address payable) public spendingAddresses;
    mapping(uint256 => address) public depositAddresses;
    mapping(uint256 => address) public wethAddresses;
    mapping(uint256 => address) public wstethAddresses;

    mapping(uint256 => address payable) public borrowAndMintAddress;
    mapping(uint256 => address) public nftAddresses;

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
        spendingAddresses[6] = payable(0xf77b584B9164d77545626d5D4263ab7a0fffeB8e); // SCROLL
        spendingAddresses[7] = payable(0xd5E66533E354A1F8cb46D7a4867d1CED40b7EeA2); // LINEA
        spendingAddresses[8] = payable(0xDEdec1fA89B6BEf042fDdEe4dA2caFbB2e42f85B); // ZKSYNC
        spendingAddresses[9] = payable(0x33a0101e2810aA0E844907F70B85c65f16A58fda); // MORPH
        spendingAddresses[10] = payable(0x0000000000000000000000000000000000000000); // FAKE ODYSSEY ID
        spendingAddresses[11] = payable(0x0000000000000000000000000000000000000000); // UNICHAIN

        depositAddresses[0] = payable(0x344DD3EF825c54f836C312CaC66294Fd2ce9F96c); // BASE
        depositAddresses[1] = payable(0xD5cE1f4A923B90dc9556bC17fBB65781cd71f5aE); // ARB
        depositAddresses[2] = payable(0xc6bA506F9E029104896F5B739487b67d4D19c1AD); // OPT
        depositAddresses[3] = payable(0x88d9872bB7eBA71254faE14E456C095DC1c5C1fA); // ETH
        depositAddresses[4] = payable(0x74f96Ed7d11e9028352F44345F4A1D35bDF7d0E4); // ZORA
        depositAddresses[5] = payable(0xF4D2D99b401859c7b825D145Ca76125455154245); // BLAST
        depositAddresses[6] = payable(0xC14C686160419cA628fAEE22475109A0c42f381f); // SCROLL
        depositAddresses[7] = payable(0x9893c446998354c4139CE7109b1f28826c2A3c92); // LINEA
        depositAddresses[8] = payable(0x2ec27C3aF391CDcEc38F2C7C48Ee8dde34F03886); // ZKSYNC
        depositAddresses[9] = payable(0xd5E66533E354A1F8cb46D7a4867d1CED40b7EeA2); // MORPH
        depositAddresses[10] = payable(0x0000000000000000000000000000000000000000); // FAKE ODYSSEY ID
        depositAddresses[11] = payable(0x0000000000000000000000000000000000000000); // UNICHAIN

        nftAddresses[0] = 0x3bcd37Ea3bB69916F156CB0BC954309bc7B7b4AC; // BASE
        nftAddresses[1] = 0x475A999e1D6A50D483A207fC8D52B583669DB90c; // ARB
        nftAddresses[2] = 0x269488db82d434dC2E08e3B6f428BD1FF90C4325; // OPT
        nftAddresses[3] = 0xe06883A0caaFe865F23597AdEDC7af4cBEaBA7E2; // ETH
        nftAddresses[4] = 0x9b6f6F895a011c2C90857596A1AE2f537B097f52; // ZORA
        nftAddresses[5] = 0x244a4b538171D0b5b7f8Ff70812CaE1d43886183; // BLAST
        
        chainIds[0] = 40245; // BASE
        chainIds[1] = 40231; // ARB
        chainIds[2] = 40232; // OPT
        chainIds[3] = 40161; // ETH
        chainIds[4] = 40249; // ZORA
        chainIds[5] = 40243; // BLAST
        chainIds[6] = 40170; // SCROLL
        chainIds[7] = 40287; // LINEA
        chainIds[8] = 40305; // ZKSYNC
        chainIds[9] = 40322; // MORPH
        chainIds[10] = 40169; // FAKE ODYSSEY ID
        chainIds[11] = 40333; // UNICHAIN

        borrowAndMintAddress[0] = payable(0x95E1EE7D40E3A2BC275153De13ECAe75B358C4e1);

        wethAddresses[0] = 0x4200000000000000000000000000000000000006; // BASE
        wethAddresses[1] = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73; // ARB
        wethAddresses[2] = 0x74A4A85C611679B73F402B36c0F84A7D2CcdFDa3; // OPT
        wethAddresses[3] = 0xf531B8F309Be94191af87605CfBf600D71C2cFe0; // ETH
        wethAddresses[4] = 0x4200000000000000000000000000000000000006; // ZORA
        wethAddresses[5] = 0x4200000000000000000000000000000000000023; // BLAST
        wethAddresses[6] = 0x5300000000000000000000000000000000000004; // SCROLL
        wethAddresses[7] = 0x10253594A832f967994b44f33411940533302ACb; // LINEA
        wethAddresses[8] = 0x84B7A6490B02Bc44aa0a7E9f60973c7cfA4dd4A9; // ZKSYNC
        wethAddresses[9] = 0x5300000000000000000000000000000000000011; // MORPH
        wethAddresses[10] = 0x582fCdAEc1D2B61c1F71FC5e3D2791B8c76E44AE; // FAKE ODYSSEY ID
        wethAddresses[11] = 0x4200000000000000000000000000000000000006; // UNICHAIN

        wstethAddresses[0] = 0x0000000000000000000000000000000000000000; // BASE
        wstethAddresses[1] = 0x0000000000000000000000000000000000000000; // ARB
        wstethAddresses[2] = 0x0000000000000000000000000000000000000000; // OPT
        wstethAddresses[3] = 0x0000000000000000000000000000000000000000; // ETH
        wstethAddresses[4] = 0x0000000000000000000000000000000000000000; // ZORA
        wstethAddresses[5] = 0x0000000000000000000000000000000000000000; // BLAST
        wstethAddresses[6] = 0x0000000000000000000000000000000000000000; // SCROLL
        wstethAddresses[7] = 0x0000000000000000000000000000000000000000; // LINEA
        wstethAddresses[8] = 0x0000000000000000000000000000000000000000; // ZKSYNC
        wstethAddresses[9] = 0x0000000000000000000000000000000000000000; // MORPH
        wstethAddresses[10] = 0x0000000000000000000000000000000000000000; // FAKE ODYSSEY ID
        wstethAddresses[11] = 0x0000000000000000000000000000000000000000; // UNICHAIN
    }

    address owner = 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140;
    address issuer1 = 0xE0D6f93151091f24EA09474e9271BD60F2624d99;
    address lz_endpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    address issuer1NftContractAddress = 0x3e19BBEe16243F36b331Ce550f3fF2685e972944;
    address opsContractAddress = 0x3d4CF5232061744CA5E72eAB6624C96750D71EC2;
    
    function run(uint8 config, uint8 chain) external {
        vm.startBroadcast();
        if (config == 1) {
            // setting up all the contracts from scratch

            spendingContract = new SmokeSpendingContract(
                wethAddresses[chain],
                owner
            );
            console.log("spendingContract", address(spendingContract));

            depositContract = new SmokeDepositContract(
                address(0),
                address(spendingContract),
                wethAddresses[chain],
                wstethAddresses[chain],
                BASEID, // adminchain ID
                chainIds[chain], // current chain ID
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
            spendingContract = SmokeSpendingContract(spendingAddresses[chain]);
            depositContract = SmokeDepositContract(depositAddresses[chain]);
            spendingContract.poolDeposit{value: 0.5 * 1e18}(
                issuer1NftContractAddress
            );

            depositContract.addSupportedToken(
                wethAddresses[chain],
                issuer1NftContractAddress
            );
            depositContract.addSupportedToken(
                wstethAddresses[chain],
                issuer1NftContractAddress
            );
        }
        else if (config == 7) {
            spendingContract = SmokeSpendingContract(spendingAddresses[chain]);
            uint256 wethBalance = IWETH2(wethAddresses[chain]).balanceOf(address(spendingContract));
            spendingContract.poolWithdraw(wethBalance, issuer1NftContractAddress);
        }
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
