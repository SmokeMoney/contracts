// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { console2 } from "forge-std/Test.sol"; // TODO REMOVE AFDTRER TEST

contract CoreNFTContract is ERC721, ERC721Enumerable, Ownable {
    using ECDSA for bytes32;

    uint256 private _currentTokenId;

    struct Account {
        mapping(address => mapping(uint256 => uint256)) walletChainLimits;
        address[] walletList;
        address[] managers;
        mapping(address => bool) autogas;
        uint256 extraLimit;
    }

    mapping(uint256 => Account) private _accounts;
    address public issuer;
    uint256 public mintPrice;
    uint256 public maxNFTs;
    uint256 public defaultExtraLimit;
    mapping(uint256 => bool) public approvedChains;
    uint256[] public chainList;
    mapping(uint256 => uint256) public lowerLimitNonces;

    uint256 public constant SIGNATURE_VALIDITY = 5 minutes;

    event ManagerAdded(uint256 indexed tokenId, address manager);
    event ManagerRemoved(uint256 indexed tokenId, address manager);
    event WalletApproved(uint256 indexed tokenId, address wallet);
    event WalletRemoved(uint256 indexed tokenId, address wallet);
    event ChainEnabled(uint256 indexed tokenId, uint256 chainId);
    event ChainDisabled(uint256 indexed tokenId, uint256 chainId);
    event WalletLimitSet(uint256 indexed tokenId, address wallet, uint256 limit);
    event ChainAdded(uint256 chainId);
    event ChainApproved(uint256 chainId);
    event ChainDisapproved(uint256 chainId);

    constructor(string memory name, string memory symbol, address _issuer, address _owner, uint256 _mintPrice, uint256 _maxNFTs) 
        ERC721(name, symbol) 
        Ownable(_owner)
    {
        issuer = _issuer;
        mintPrice = _mintPrice;
        maxNFTs = _maxNFTs;
    }

    modifier onlyIssuer() {
        require(msg.sender == issuer, "Not the issuer");
        _;
    }

    function mint() external payable returns (uint256) {
        require(msg.value >= mintPrice, "Insufficient payment");
        require(_currentTokenId <= maxNFTs, "Max NFTs minted");

        _currentTokenId++;
        uint256 newTokenId = _currentTokenId;
        _accounts[newTokenId].extraLimit = defaultExtraLimit;
        _safeMint(msg.sender, newTokenId);
        return newTokenId;
    }

    function approveChain(uint256 chainId) external onlyIssuer {
        if (!isChainInList(chainId)) {
            chainList.push(chainId);
            emit ChainAdded(chainId);
        }
        approvedChains[chainId] = true;
        emit ChainApproved(chainId);
    }

    function disapproveChain(uint256 chainId) external onlyIssuer {
        approvedChains[chainId] = false;
        emit ChainDisapproved(chainId);
    }

    function isChainInList(uint256 chainId) public view returns (bool) {
        for (uint i = 0; i < chainList.length; i++) {
            if (chainList[i] == chainId) {
                return true;
            }
        }
        return false;
    }

    function isManagerOrOwner(uint256 tokenId, address addr) public view returns (bool) {
        return ownerOf(tokenId) == addr || isManager(tokenId, addr);
    }

    function isManager(uint256 tokenId, address addr) public view returns (bool) {
        Account storage account = _accounts[tokenId];
        for (uint i = 0; i < account.managers.length; i++) {
            if (account.managers[i] == addr) {
                return true;
            }
        }
        return false;
    }

    function addManager(uint256 tokenId, address manager) external {
        require(ownerOf(tokenId) == msg.sender, "Not the token owner");
        require(!isManager(tokenId, manager), "Already a manager");
        _accounts[tokenId].managers.push(manager);
        emit ManagerAdded(tokenId, manager);
    }

    function removeManager(uint256 tokenId, address manager) external {
        require(ownerOf(tokenId) == msg.sender, "Not the token owner");
        Account storage account = _accounts[tokenId];
        for (uint i = 0; i < account.managers.length; i++) {
            if (account.managers[i] == manager) {
                account.managers[i] = account.managers[account.managers.length - 1];
                account.managers.pop();
                emit ManagerRemoved(tokenId, manager);
                return;
            }
        }
        revert("Manager not found");
    }

    function setHigherLimit(uint256 tokenId, address wallet, uint256 chainId, uint256 newLimit) external {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        if (!isWalletAdded(tokenId, wallet)) {
            _accounts[tokenId].walletList.push(wallet);
        }
        _setHigherLimit(tokenId, wallet, chainId, newLimit);
    }

    function setHigherBulkLimits(
        uint256 tokenId,
        address wallet,
        uint256[] memory chainIds,
        uint256[] memory newLimits,
        bool autogas
    ) external {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        if (!isWalletAdded(tokenId, wallet)) {
            _accounts[tokenId].walletList.push(wallet);
        }
        require(chainIds.length == newLimits.length, "Limits leagth should match the chain List length");
        for (uint256 i = 0; i < chainIds.length; i++) {
            _setHigherLimit(tokenId, wallet, chainIds[i], newLimits[i]);
        }
        _accounts[tokenId].autogas[wallet] = autogas;
    }

    function _setHigherLimit(uint256 tokenId, address wallet, uint256 chainId, uint256 newLimit) internal {
        require(approvedChains[chainId], "Chain not approved by the issuer");
        uint256 currentLimit = _accounts[tokenId].walletChainLimits[wallet][chainId];
        require(newLimit >= currentLimit, "New limit must be higher than current limit");
        _accounts[tokenId].walletChainLimits[wallet][chainId] = newLimit;
    }

    function setLowerLimit(
        uint256 tokenId,
        address wallet,
        uint256 chainId,
        uint256 newLimit,
        uint256 timestamp,
        uint256 nonce, 
        bytes memory signature
    ) external {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        require(isWalletAdded(tokenId, wallet), "Wallet not added");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(nonce == lowerLimitNonces[tokenId], "Invalid limit change nonce");

        bytes32 messageHash = keccak256(abi.encodePacked(tokenId, wallet, chainId, newLimit, timestamp, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuer, "Invalid signature");

        _accounts[tokenId].walletChainLimits[wallet][chainId] = newLimit;
        lowerLimitNonces[tokenId]++;
    }

    function setLowerBulkLimits(
        uint256 tokenId,
        address wallet,
        uint256[] memory chainIds,
        uint256[] memory newLimits,
        uint256 timestamp,
        uint256 nonce,
        bytes memory signature
    ) external {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        require(isWalletAdded(tokenId, wallet), "Wallet not added");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(chainIds.length == newLimits.length, "Limits leagth should match the chain List length");
        require(nonce == lowerLimitNonces[tokenId], "Invalid limit change nonce");

        bytes32 messageHash = keccak256(abi.encode(tokenId, wallet, chainIds, newLimits, timestamp, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuer, "Invalid signature");

        for (uint256 i = 0; i < chainIds.length; i++) {
            _accounts[tokenId].walletChainLimits[wallet][chainIds[i]] = newLimits[i];
        }
        lowerLimitNonces[tokenId]++;
    }

    function resetWalletChainLimits(
        uint256 tokenId,
        address wallet,
        uint256 timestamp,
        uint256 nonce,
        bytes memory signature
    ) public {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(nonce == lowerLimitNonces[tokenId], "Invalid limit change nonce");

        bytes32 messageHash = keccak256(abi.encodePacked(tokenId, wallet, timestamp, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuer, "Invalid signature");

        for (uint i = 0; i < chainList.length; i++) {
            delete _accounts[tokenId].walletChainLimits[wallet][chainList[i]];
        }
        lowerLimitNonces[tokenId]++;
    }

    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function setMintPrice(uint256 _mintPrice) external onlyOwner {
        mintPrice = _mintPrice;
    }

    function setMaxNFTs(uint256 _maxNFTs) external onlyOwner {
        require(_maxNFTs >= _currentTokenId, "Cannot set max lower than current total");
        maxNFTs = _maxNFTs;
    }

    function withdrawFunds() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function setExtraLimit(uint256 tokenId, uint256 _extraLimit) external onlyIssuer {
        require(_extraLimit > _accounts[tokenId].extraLimit);
        _accounts[tokenId].extraLimit = _extraLimit;
    }

    function setBulkExtraLimits(uint256[] calldata tokenIds, uint256 _extraLimit) external onlyIssuer {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(_extraLimit > _accounts[tokenIds[i]].extraLimit, "New limit must be higher than old");
            _accounts[tokenIds[i]].extraLimit = _extraLimit;
        }
    }

    function setDefaultExtraLimit(uint256 _extraLimit) external onlyIssuer {
        defaultExtraLimit = _extraLimit;
    }

    function setAutogasForWallet(uint256 tokenId, address wallet, bool autogas) external {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        require(isWalletAdded(tokenId, wallet), "Wallet not added");
        _accounts[tokenId].autogas[wallet] = autogas;
    }

    function getManagers(uint256 tokenId) external view returns (address[] memory) {
        return _accounts[tokenId].managers;
    }

    function getAutogasConfig(uint256 tokenId, address wallet) external view returns (bool) {
        return _accounts[tokenId].autogas[wallet];
    }

    function getExtraLimit(uint256 tokenId) external view returns (uint256) {
        return _accounts[tokenId].extraLimit;
    }
    
    function getWallets(uint256 tokenId) external view returns (address[] memory) {
        return _accounts[tokenId].walletList;
    }       

    function isWalletAdded(uint256 tokenId, address wallet) public view returns (bool) {
        address[] memory wallets = _accounts[tokenId].walletList;
        for (uint i = 0; i < wallets.length; i++) {
            if (wallets[i] == wallet) {
                return true;
            }
        }
        return false;
    }

    function getChainList() external view returns (uint256[] memory) {
        return chainList;
    }

    function getWalletChainLimit(uint256 tokenId, address wallet, uint256 chainId) external view returns (uint256) {
        return _accounts[tokenId].walletChainLimits[wallet][chainId];
    }

    function _getWalletChainLimit(uint256 tokenId, address wallet, uint256 chainId) internal view returns (uint256) {
        return _accounts[tokenId].walletChainLimits[wallet][chainId];
    }

    function getWalletsWithLimitChain(uint256 tokenId, uint256 chainId) external view returns (address[] memory) {
        // First, count the number of wallets with limits
        uint256 count = 0;
        for (uint256 i = 0; i < _accounts[tokenId].walletList.length; i++) {
            if (_getWalletChainLimit(tokenId, _accounts[tokenId].walletList[i], chainId) > 0) {
                count++;
            }
        }
    
        // Create a fixed-size array with the correct length
        address[] memory walletsWithLimits = new address[](count);
    
        // Fill the array
        uint256 index = 0;
        for (uint256 i = 0; i < _accounts[tokenId].walletList.length; i++) {
            if (_getWalletChainLimit(tokenId, _accounts[tokenId].walletList[i], chainId) > 0) {
                walletsWithLimits[index] = _accounts[tokenId].walletList[i];
                index++;
            }
        }
    
        return walletsWithLimits;
    }

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
