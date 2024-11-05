// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SimpleNFT is ERC721, Ownable {
    uint256 private _tokenIds;

    uint256 public constant MINT_PRICE = 0.002 ether;
    uint256 public constant MAX_SUPPLY = 100000;

    constructor() ERC721("Smoke NFT", "SNFT") Ownable(msg.sender) {}

    function mint() public payable returns (uint256) {
        require(msg.value >= MINT_PRICE, "Insufficient payment");
        require(_tokenIds < MAX_SUPPLY, "Max supply reached");

        ++_tokenIds;
        uint256 newTokenId = _tokenIds;
        _safeMint(msg.sender, newTokenId);
        return newTokenId;
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIds;
    }
}