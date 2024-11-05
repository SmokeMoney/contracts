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

        nftAddresses[0] = 0x3bcd37Ea3bB69916F156CB0BC954309bc7B7b4AC; // BASE
        nftAddresses[1] = 0x475A999e1D6A50D483A207fC8D52B583669DB90c; // ARB
        nftAddresses[2] = 0x269488db82d434dC2E08e3B6f428BD1FF90C4325; // OPT
        nftAddresses[3] = 0xe06883A0caaFe865F23597AdEDC7af4cBEaBA7E2; // ETH
        nftAddresses[4] = 0x9b6f6F895a011c2C90857596A1AE2f537B097f52; // ZORA
        nftAddresses[5] = 0x244a4b538171D0b5b7f8Ff70812CaE1d43886183; // BLAST

        borrowAndMintAddress[0] = payable(0x95E1EE7D40E3A2BC275153De13ECAe75B358C4e1);
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
            smokeNftContract = SimpleNFT(0xf5C17b101ad431d2eD9443360A5f6474C5471860);
            smokeNftContract.mint{value: 2e15}();
        }
        else if (config == 3) {
            borrowAndM = BorrowAndMintNFT(borrowAndMintAddress[chain]);

            IBorrowContract.BorrowParams memory bP = IBorrowContract.BorrowParams({
                borrower: 0xa2A53973a147F2996F3f33c363Af0f22Dc46c549,
                issuerNFT: 0x3e19BBEe16243F36b331Ce550f3fF2685e972944,
                nftId: 1,
                amount: 2000000000000000,
                timestamp: 1727766397,
                signatureValidity: 1200,
                nonce: 29,
                repayGas: 2e14,
                weth: false,
                recipient: 0x95E1EE7D40E3A2BC275153De13ECAe75B358C4e1,
                integrator: 0
            });
            bytes
                memory userSignature = hex"15f967f0c636d7bd46eb23e49f9f4c0e635feb4e11656679b75079415e3cf1d93f4b82dcc7dbe2cc0795485258f872cefe0ac0824dbea15912d2696fdd3e5bd81c";
            bytes
                memory issuerSignature = hex"0e4b4f74e782e48acdf2d9819a35f90018c70b100ae0885b1f29ee01bd285aca33cb090ebc07724f8ea286e38cf31d1ffd215222f96276da1c8e537ab3810b5e1b";

            borrowAndM.borrowAndMint(bP, userSignature, issuerSignature, nftAddresses[chain]);
        }
        else if (config == 4) {
            smokeNftContract = SimpleNFT(nftAddresses[chain]);
            smokeNftContract.withdraw();
        }
        vm.stopBroadcast();
    }
}
