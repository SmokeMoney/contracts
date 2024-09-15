// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BorrowAndMint.sol";
import "../src/SmokeSpendingContract.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract SimpleNFT is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    uint256 public constant MINT_PRICE = 0.002 ether;
    uint256 public constant MAX_SUPPLY = 1000;

    constructor() ERC721("Smoke NFT Optimism", "SNFT") Ownable(msg.sender) {}

    function mint() public payable returns (uint256) {
        require(msg.value >= MINT_PRICE, "Insufficient payment");
        require(_tokenIds.current() < MAX_SUPPLY, "Max supply reached");

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _safeMint(msg.sender, newTokenId);
        return newTokenId;
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIds.current();
    }
}

contract SetupScript is Script {
    BorrowAndMintNFT borrowAndM;
    SimpleNFT smokeNftContract;
    address spendingContractBase = 0x67077b70711026CE9d7C3f591D45924264a0c65b;

    function run() external {
        vm.startBroadcast();
        smokeNftContract = SimpleNFT(0xD1F1Fc828205B65290093939c279E21be59c8916);
        // borrowAndM = new BorrowAndMintNFT(spendingContractBase, address(smokeNftContract));
        smokeNftContract.withdraw();
        console.log("Smoke NFT", address(smokeNftContract));
        console.log("BorrowAndMint", address(borrowAndM));
        // borrowAndM = BorrowAndMintNFT(
        //     payable(0xf1e095f77280FFBBd941a6655F0aa8a1d686aA2D)
        // );

        // IBorrowContract.BorrowParams memory bP = IBorrowContract.BorrowParams({
        //     borrower: 0xa2A53973a147F2996F3f33c363Af0f22Dc46c549,
        //     issuerNFT: 0x3e19BBEe16243F36b331Ce550f3fF2685e972944,
        //     nftId: 1,
        //     amount: 2000000000000000,
        //     timestamp: 1726329331,
        //     signatureValidity: 1200,
        //     nonce: 5,
        //     repayGas: 0,
        //     weth: false,
        //     recipient: 0xf1e095f77280FFBBd941a6655F0aa8a1d686aA2D,
        //     integrator: 0
        // });
        // bytes
        //     memory userSignature = hex"cb851f4d93f5b0f76931742294b75f80d21eabb1e74384f07baae550c69e0f753389f90386bcb72c0395f90267dc204f4adad06a6bcd560c744d6a4143a2fd1c1b";
        // bytes
        //     memory issuerSignature = hex"e3375dfe917dee461dcf3d8de44329fd767314f1fdd4045d792e17e934fdca087a48372177d4aa958126b003fbe23611c6f1bf0aa528b441403d722ea85a5b4b1b";

        // borrowAndM.borrowAndMint(bP, userSignature, issuerSignature);

        vm.stopBroadcast();
    }
}
