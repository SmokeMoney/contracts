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
    uint32 BASEID = 30184;
    mapping(uint256 => uint32) public chainIds;
    mapping(uint256 => address) public depositAddresses;
    mapping(uint256 => address payable) public spendingAddresses;
    mapping(uint256 => address) public wethAddresses;
    mapping(uint256 => address) public wstethAddresses;

    WstETHOracleReceiver wstETHOracle;
    AssemblePositionsContract assemblePositionsContract;
    OperationsContract accountOps;
    CoreNFTContract issuer1NftContract;
    SmokeSpendingContract spendingContract;
    SmokeDepositContract depositContract;

    address owner = 0x03773f85756acaC65A869e89E3B7b2fcDA6Be140;
    address issuer1 = 0x8558519aD14B443949149577024A92C036BEb7Bb;
    address lz_endpoint = 0x1a44076050125825900e736c501f859c50fE728c;

    address issuer1NftContractAddress = 0x794F11F77cd0D4eE60885A1a1857d796f0D08fd7;
    address opsContractAddress = 0x2Cbe484B1E2fe4ffA28Fef0cAa0C9E0D724Fe183;

    constructor() {
        setupAddresses();
    }

    function setupAddresses() internal {
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

        spendingAddresses[100] = payable(0xf430ac9B73c5fb875d8350A300E95049a19CAbb1); // BASE
        spendingAddresses[101] = payable(0x9cA9D67f613c50741E30e5Ef88418891e254604d); // ARB
        spendingAddresses[102] = payable(0xf430ac9B73c5fb875d8350A300E95049a19CAbb1); // OPT
        spendingAddresses[103] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ETH
        spendingAddresses[104] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ZORA
        spendingAddresses[105] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // BLAST
        spendingAddresses[106] = payable(0x9cA9D67f613c50741E30e5Ef88418891e254604d); // SCROLL
        spendingAddresses[107] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // LINEA
        spendingAddresses[108] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ZKSYNC
        spendingAddresses[109] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // MORPH
        spendingAddresses[110] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ODYSSEY
        spendingAddresses[111] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // UNICHAIN

        depositAddresses[100] = payable(0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B); // BASE
        depositAddresses[101] = payable(0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59); // ARB
        depositAddresses[102] = payable(0x472Cf1b83213DeD59DB4Fc643532d07450d8f40B); // OPT
        depositAddresses[103] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ETH
        depositAddresses[104] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ZORA
        depositAddresses[105] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // BLAST
        depositAddresses[106] = payable(0xeEbe5E1bD522BbD9a64f28d923c0680F89DB5c59); // SCROLL
        depositAddresses[107] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // LINEA
        depositAddresses[108] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ZKSYNC
        depositAddresses[109] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // MORPH
        depositAddresses[110] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // ODYSSEY
        depositAddresses[111] = payable(0x14440344256002a5afaA1403EbdAf4bf9a5499E3); // UNICHAIN

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

    }

    function run(uint8 config) external {
        vm.startBroadcast();
        if (config == 1) {
            // setting up all the contracts from scratch
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
                lz_endpoint, // LZ endpoint
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

            spendingContract = new SmokeSpendingContract(wethAddresses[100], owner);
            console.log("spendingContract", address(spendingContract));

            depositContract = new SmokeDepositContract(
                address(accountOps),
                address(spendingContract),
                wethAddresses[100],
                wstethAddresses[100],
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
        } else if (config == 2) {
            // setting deposit addresses and wiring contracts
            accountOps = OperationsContract(opsContractAddress);

            for (uint256 i = 100; i < 103; i++) {
                accountOps.setDepositContract(chainIds[i], depositAddresses[i]); // Adding the deposit contract on the local chain
            }

            for (uint256 i = 101; i < 103; i++) {
                accountOps.setPeer(chainIds[i], addressToBytes32(depositAddresses[i]));
            }
        } else if (config == 3) {
            spendingContract = SmokeSpendingContract(spendingAddresses[100]);
            depositContract = SmokeDepositContract(depositAddresses[100]);
            issuer1NftContract = CoreNFTContract(issuer1NftContractAddress);
            spendingContract.poolDeposit{value: 0.0042 * 1e18}(issuer1NftContractAddress);

            for (uint256 i = 100; i < 103; i++) {
                issuer1NftContract.approveChain(chainIds[i]);
            }

            issuer1NftContract.setDefaultNativeCredit(2000000000000000);

            depositContract.addSupportedToken(wethAddresses[100], issuer1NftContractAddress);
            depositContract.addSupportedToken(wstethAddresses[100], issuer1NftContractAddress);
        } else if (config == 4) {
            // add new chian
            accountOps = OperationsContract(opsContractAddress);

            accountOps.setDepositContract(chainIds[106], depositAddresses[106]); // Adding the deposit contract on the local chain
            accountOps.setPeer(chainIds[106], addressToBytes32(depositAddresses[106]));
        } else if (config == 5) {
            // with issuer address
            issuer1NftContract = CoreNFTContract(issuer1NftContractAddress);
            issuer1NftContract.approveChain(chainIds[106]);
        } else if (config == 6) {
            spendingContract = SmokeSpendingContract(spendingAddresses[100]);
            issuer1NftContract = new CoreNFTContract(
                "Smoke OG",
                "OG",
                issuer1,
                0.002 * 1e18, // mint price
                10 // max nfts
            );
            console.log("issuer1NftContract", address(issuer1NftContract));

            spendingContract.addIssuer(
                address(issuer1NftContract),
                issuer1,
                1000, // borrow interest 10%
                1e15, // autogasThreshold 0.001 ETH
                1e15, // autogasRefill 0.001 ETH
                2 // gas price threshold
            );
        } else if (config == 7) {
            spendingContract = SmokeSpendingContract(spendingAddresses[100]);
            uint256 wethBalance = IWETH2(wethAddresses[100]).balanceOf(address(spendingContract));
            spendingContract.poolWithdraw(wethBalance, issuer1NftContractAddress);
        }
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
