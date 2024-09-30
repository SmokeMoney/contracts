// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "../src/BorrowAndMint.sol";
import "../src/SmokeSpendingContract.sol";
import "../src/SimpleNFT.sol";

contract SetupScript is Script {
    BorrowAndMintNFT borrowAndM;
    SimpleNFT smokeNftContract;
    mapping(uint256 => address payable) public spendingAddresses;
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

        nftAddresses[0] = 0xD1F1Fc828205B65290093939c279E21be59c8916; // BASE
    }

    address payable spending_BAS_Address = payable(0x67077b70711026CE9d7C3f591D45924264a0c65b);
    address payable spending_ARB_Address = payable(0xACdB62538dB30EF5F9Cdb4F7E0640f856708449d);
    address payable spending_OPT_Address = payable(0xa1971bF0cEa6A6Fe47447914b0AB20118CF7B845);
    address payable spending_ETH_Address = payable(0x78DdB60EbD01D547164F4057C3d36948A66106b6);
    address payable spending_ZORA_Address = payable(0x73f0b82ea0C7268866Bb39E5a30f3f4E348E3FeB);
    address payable spending_BLAST_Address = payable(0x9b6f6F895a011c2C90857596A1AE2f537B097f52);

    function run(uint8 config, uint8 chain) external {
        vm.startBroadcast();
        if (config == 1) {
            borrowAndM = new BorrowAndMintNFT(spendingAddresses[chain]);
            smokeNftContract = new SimpleNFT();
            console.log("Smoke NFT", address(smokeNftContract));
            console.log("BorrowAndMint", address(borrowAndM));
        }
        else if (config == 2){
            smokeNftContract = SimpleNFT(0xD1F1Fc828205B65290093939c279E21be59c8916);
            smokeNftContract.withdraw();
        }
        else if (config == 3) {
            borrowAndM = BorrowAndMintNFT(
                payable(0xf1e095f77280FFBBd941a6655F0aa8a1d686aA2D)
            );

            IBorrowContract.BorrowParams memory bP = IBorrowContract.BorrowParams({
                borrower: 0xa2A53973a147F2996F3f33c363Af0f22Dc46c549,
                issuerNFT: 0x3e19BBEe16243F36b331Ce550f3fF2685e972944,
                nftId: 1,
                amount: 2000000000000000,
                timestamp: 1726329331,
                signatureValidity: 1200,
                nonce: 5,
                repayGas: 0,
                weth: false,
                recipient: 0xf1e095f77280FFBBd941a6655F0aa8a1d686aA2D,
                integrator: 0
            });
            bytes
                memory userSignature = hex"cb851f4d93f5b0f76931742294b75f80d21eabb1e74384f07baae550c69e0f753389f90386bcb72c0395f90267dc204f4adad06a6bcd560c744d6a4143a2fd1c1b";
            bytes
                memory issuerSignature = hex"e3375dfe917dee461dcf3d8de44329fd767314f1fdd4045d792e17e934fdca087a48372177d4aa958126b003fbe23611c6f1bf0aa528b441403d722ea85a5b4b1b";

            borrowAndM.borrowAndMint(bP, userSignature, issuerSignature, nftAddresses[chain]);
        }
        vm.stopBroadcast();
    }
}
