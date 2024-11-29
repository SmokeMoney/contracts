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
    mapping(uint256 => address) public lzEndpointAddress;

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
        spendingAddresses[10] = payable(0x0000000000000000000000000000000000000000); // ODYSSEY
        spendingAddresses[11] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // UNICHAIN

        spendingAddresses[100] = payable(0xf430ac9B73c5fb875d8350A300E95049a19CAbb1); // BASE
        spendingAddresses[101] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ARB
        spendingAddresses[102] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // OPT
        spendingAddresses[103] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ETH
        spendingAddresses[104] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ZORA
        spendingAddresses[105] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // BLAST
        spendingAddresses[106] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // SCROLL
        spendingAddresses[107] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // LINEA
        spendingAddresses[108] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ZKSYNC
        spendingAddresses[109] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // MORPH
        spendingAddresses[110] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ODYSSEY
        spendingAddresses[111] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // UNICHAIN

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
        depositAddresses[11] = payable(0xDF52714C191e8C4EC26cCD5B1578a904724e93b6); // UNICHAIN

        depositAddresses[100] = payable(0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B); // BASE
        depositAddresses[101] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ARB
        depositAddresses[102] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // OPT
        depositAddresses[103] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ETH
        depositAddresses[104] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ZORA
        depositAddresses[105] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // BLAST
        depositAddresses[106] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // SCROLL
        depositAddresses[107] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // LINEA
        depositAddresses[108] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ZKSYNC
        depositAddresses[109] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // MORPH
        depositAddresses[110] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ODYSSEY
        depositAddresses[111] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // UNICHAIN

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
        chainIds[10] = 40340; // ODYSSEY
        chainIds[11] = 40333; // UNICHAIN

        chainIds[100] = 30184; // BASE
        chainIds[101] = 30110; // ARB
        chainIds[102] = 30111; // OPT
        chainIds[103] = 30101; // ETH
        chainIds[104] = 30195; // ZORA
        chainIds[105] = 30243; // BLAST
        chainIds[106] = 30214; // SCROLL
        chainIds[107] = 30183; // LINEA
        chainIds[108] = 30165; // ZKSYNC
        chainIds[109] = 30322; // MORPH
        chainIds[110] = 40340; // ODYSSEY
        chainIds[111] = 40333; // UNICHAIN

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
        wethAddresses[11] = 0x4200000000000000000000000000000000000006; // UNICHAI

        wethAddresses[100] = 0x4200000000000000000000000000000000000006; // BASE
        wethAddresses[101] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // ARB
        wethAddresses[102] = 0x4200000000000000000000000000000000000006; // OPT
        wethAddresses[103] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // ETH
        wethAddresses[104] = 0x4200000000000000000000000000000000000006; // ZORA
        wethAddresses[105] = 0x4300000000000000000000000000000000000004; // BLAST
        wethAddresses[106] = 0x5300000000000000000000000000000000000004; // SCROLL
        wethAddresses[107] = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f; // LINEA
        wethAddresses[108] = 0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91; // ZKSYNC
        wethAddresses[109] = 0x5300000000000000000000000000000000000011; // MORPH
        wethAddresses[110] = 0x0000000000000000000000000000000000000000; // ODYSSEY
        wethAddresses[111] = 0x0000000000000000000000000000000000000000; // UNICHAIN

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
        wstethAddresses[11] = 0x0000000000000000000000000000000000000000; // UNICHAINN

        wstethAddresses[100] = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452; // BASE
        wstethAddresses[101] = 0x0fBcbaEA96Ce0cF7Ee00A8c19c3ab6f5Dc8E1921; // ARB
        wstethAddresses[102] = 0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb; // OPT
        wstethAddresses[103] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; // ETH
        wstethAddresses[104] = 0x0000000000000000000000000000000000000000; // ZORA
        wstethAddresses[105] = 0x0000000000000000000000000000000000000000; // BLAST
        wstethAddresses[106] = 0xf610A9dfB7C89644979b4A0f27063E9e7d7Cda32; // SCROLL
        wstethAddresses[107] = 0xB5beDd42000b71FddE22D3eE8a79Bd49A568fC8F; // LINEA
        wstethAddresses[108] = 0x703b52F2b28fEbcB60E1372858AF5b18849FE867; // ZKSYNC
        wstethAddresses[109] = 0x0000000000000000000000000000000000000000; // MORPH
        wstethAddresses[110] = 0x0000000000000000000000000000000000000000; // ODYSSEY
        wstethAddresses[111] = 0x0000000000000000000000000000000000000000; // UNICHAIN

        lzEndpointAddress[0] = 0x6EDCE65403992e310A62460808c4b910D972f10f; // BASE
        lzEndpointAddress[1] = 0x6EDCE65403992e310A62460808c4b910D972f10f; // ARB
        lzEndpointAddress[2] = 0x6EDCE65403992e310A62460808c4b910D972f10f; // OPT
        lzEndpointAddress[3] = 0x6EDCE65403992e310A62460808c4b910D972f10f; // ETH
        lzEndpointAddress[4] = 0x6EDCE65403992e310A62460808c4b910D972f10f; // ZORA
        lzEndpointAddress[5] = 0x6EDCE65403992e310A62460808c4b910D972f10f; // BLAST
        lzEndpointAddress[6] = 0x6EDCE65403992e310A62460808c4b910D972f10f; // SCROLL
        lzEndpointAddress[7] = 0x6EDCE65403992e310A62460808c4b910D972f10f; // LINEA
        lzEndpointAddress[8] = 0xe2Ef622A13e71D9Dd2BBd12cd4b27e1516FA8a09; // ZKSYNC
        lzEndpointAddress[9] = 0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff; // MORPH
        lzEndpointAddress[10] = 0x6Ac7bdc07A0583A362F1497252872AE6c0A5F5B8; // FAKE ODYSSEY ID
        lzEndpointAddress[11] = 0xb8815f3f882614048CbE201a67eF9c6F10fe5035; // UNICHAIN

        lzEndpointAddress[100] = 0x1a44076050125825900e736c501f859c50fE728c; // BASE
        lzEndpointAddress[101] = 0x1a44076050125825900e736c501f859c50fE728c; // ARB
        lzEndpointAddress[102] = 0x1a44076050125825900e736c501f859c50fE728c; // OPT
        lzEndpointAddress[103] = 0x1a44076050125825900e736c501f859c50fE728c; // ETH
        lzEndpointAddress[104] = 0x1a44076050125825900e736c501f859c50fE728c; // ZORA
        lzEndpointAddress[105] = 0x1a44076050125825900e736c501f859c50fE728c; // BLAST
        lzEndpointAddress[106] = 0x1a44076050125825900e736c501f859c50fE728c; // SCROLL
        lzEndpointAddress[107] = 0x1a44076050125825900e736c501f859c50fE728c; // LINEA
        lzEndpointAddress[108] = 0xd07C30aF3Ff30D96BDc9c6044958230Eb797DDBF; // ZKSYNC
        lzEndpointAddress[109] = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B; // MORPH
        lzEndpointAddress[110] = 0x0000000000000000000000000000000000000000; // ODYSSEY
        lzEndpointAddress[111] = 0x0000000000000000000000000000000000000000; // UNICHAIN
    }

    address owner = 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140;
    address issuer1 = 0xE0D6f93151091f24EA09474e9271BD60F2624d99;

    address issuer1NftContractAddress = 0x3e19BBEe16243F36b331Ce550f3fF2685e972944;
    address opsContractAddress = 0x3d4CF5232061744CA5E72eAB6624C96750D71EC2;

    function run(uint8 config, uint8 chain) external {
        vm.startBroadcast();
        if (config == 1) {
            // setting up all the contracts from scratch

            spendingContract = new SmokeSpendingContract(wethAddresses[chain], owner);
            console.log("spendingContract", address(spendingContract));

            depositContract = new SmokeDepositContract(
                address(0),
                address(spendingContract),
                wethAddresses[chain],
                wstethAddresses[chain],
                chainIds[100], // adminchain ID
                chainIds[chain], // current chain ID
                lzEndpointAddress[chain],
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
                chainIds[100], // adminchain ID
                addressToBytes32(opsContractAddress)
            );
        } else if (config == 3) {
            spendingContract = SmokeSpendingContract(spendingAddresses[chain]);
            depositContract = SmokeDepositContract(depositAddresses[chain]);
            spendingContract.poolDeposit{value: 0.5 * 1e18}(issuer1NftContractAddress);

            depositContract.addSupportedToken(wethAddresses[chain], issuer1NftContractAddress);
            depositContract.addSupportedToken(wstethAddresses[chain], issuer1NftContractAddress);
        } else if (config == 7) {
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
