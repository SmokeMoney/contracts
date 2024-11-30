// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IBorrowContract {
    struct BorrowParams {
        address borrower;
        address issuerNFT;
        uint256 nftId;
        uint256 amount;
        uint256 timestamp;
        uint256 signatureValidity;
        uint256 nonce;
        uint256 repayGas;
        bool weth;
        address recipient;
        uint256 integrator;
    }

    function borrowWithSignature(BorrowParams memory params, bytes memory userSignature, bytes memory issuerSignature)
        external
        payable;
}

contract BorrowAndSwapERC20 is Ownable, ReentrancyGuard {
    IBorrowContract public borrowContract;

    constructor(address _borrowContract) Ownable(msg.sender) {
        borrowContract = IBorrowContract(_borrowContract);
    }

    function borrowAndSwap(
        IBorrowContract.BorrowParams memory borrowParams,
        bytes memory userSignature,
        bytes memory issuerSignature,
        address erc20Contract
    ) external nonReentrant {
        require(!borrowParams.weth, "Must borrow ETH for swapping");
        require(borrowParams.recipient == address(this), "Recipient must be this contract");

        uint256 initialBalance = address(this).balance;

        borrowContract.borrowWithSignature(borrowParams, userSignature, issuerSignature);

        uint256 borrowedAmount = address(this).balance - initialBalance;
        require(
            borrowedAmount == borrowParams.amount + borrowParams.repayGas,
            "Borrowed amount doesn't match expected amount"
        );

        // User actions here
        // INFTMintContract nftMintContract = INFTMintContract(_nftMintContract);
        // uint256 newTokenId = nftMintContract.mint{value: borrowParams.amount}();
        // nftMintContract.safeTransferFrom(address(this), borrowParams.borrower, newTokenId);
        // User actions end here

        if (borrowParams.repayGas > 0) {
            (bool success,) = msg.sender.call{value: borrowParams.repayGas}("");
            require(success, "Failed to send repayGas to msg.sender");
        }
    }

    // Function to handle receiving ETH
    receive() external payable {}

    // Function to withdraw any accidentally sent ETH
    function withdraw(uint256 amount) external onlyOwner {
        payable(owner()).transfer(amount);
    }

    // Function to withdraw any accidentally sent ERC721 tokens
    function withdrawERC721(address tokenAddress, uint256 tokenId) external onlyOwner {
        IERC721(tokenAddress).safeTransferFrom(address(this), owner(), tokenId);
    }
}
