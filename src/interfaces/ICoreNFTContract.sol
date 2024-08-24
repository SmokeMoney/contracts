// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICoreNFTContract {
    function ownerOf(uint256 nftId) external view returns (address);

    function isManagerOrOwner(
        uint256 nftId,
        address addr
    ) external view returns (bool);

    function isWalletAdded(
        uint256 nftId,
        bytes32 wallet
    ) external view returns (bool);

    function getWallets(uint256 nftId) external view returns (bytes32[] memory);

    function getGNFTList(
        uint256 nftId
    ) external view returns (uint256[] memory);

    function getPWalletsTotalLimit(
        uint256 nftId
    ) external view returns (uint256);

    function getGWallet(uint256 gNFT) external view returns (bytes32);

    function getWalletChainLimit(
        uint256 nftId,
        bytes32 wallet,
        uint256 chainId
    ) external view returns (uint256);

    function getWalletsWithLimitChain(
        uint256 nftId,
        uint256 chainId
    ) external view returns (bytes32[] memory);

    function getNativeCredit(uint256 nftId) external view returns (uint256);

    function getChainList() external view returns (uint256[] memory);

    function owner() external view returns (address);

    function getGNFTCount(uint256 nftId) external view returns (uint256);

    function getTotalSupply() external pure returns (uint256);
}
