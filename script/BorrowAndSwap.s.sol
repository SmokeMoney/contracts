// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "../src/BorrowAndSwap.sol";
import "../src/SmokeSpendingContract.sol";
import "../src/SimpleNFT.sol";

contract SetupScript is Script {
    BorrowAndSwapERC20 borrowAndSwap;
    SimpleNFT smokeNftContract;
    mapping(uint256 => address payable) public spendingAddresses;
    mapping(uint256 => address) public lifiDiamond;
    mapping(uint256 => address payable) public borrowAndMintAddress;

    constructor() {
        setupAddresses();
    }

    function setupAddresses() internal {
        spendingAddresses[100] = payable(0xf430ac9B73c5fb875d8350A300E95049a19CAbb1); // BASE
        spendingAddresses[101] = payable(0x9cA9D67f613c50741E30e5Ef88418891e254604d); // ARB
        spendingAddresses[102] = payable(0xf430ac9B73c5fb875d8350A300E95049a19CAbb1); // OPT

        lifiDiamond[100] = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE; // BASE
        lifiDiamond[101] = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE; // ARB
        lifiDiamond[102] = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE; // OPT

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
            borrowAndSwap = new BorrowAndSwapERC20(spendingAddresses[chain], lifiDiamond[chain]);
            console.log("borrowAndSwap", address(borrowAndSwap));
        } else if (config == 2) {
            smokeNftContract = SimpleNFT(0xf5C17b101ad431d2eD9443360A5f6474C5471860);
            smokeNftContract.mint{value: 2e15}();
        } else if (config == 3) {
            borrowAndSwap = BorrowAndSwapERC20(borrowAndMintAddress[chain]);

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
            bytes memory userSignature =
                hex"15f967f0c636d7bd46eb23e49f9f4c0e635feb4e11656679b75079415e3cf1d93f4b82dcc7dbe2cc0795485258f872cefe0ac0824dbea15912d2696fdd3e5bd81c";
            bytes memory issuerSignature =
                hex"0e4b4f74e782e48acdf2d9819a35f90018c70b100ae0885b1f29ee01bd285aca33cb090ebc07724f8ea286e38cf31d1ffd215222f96276da1c8e537ab3810b5e1b";

            // borrowAndSwap.borrowAndSwap(bP, userSignature, issuerSignature, lifiDiamond[chain]);
        }
        vm.stopBroadcast();
    }
}
