// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import { console2 } from "forge-std/Test.sol"; // TODO REMOVE AFDTRER TEST

contract CoreNFTContract is ERC721, ERC721Enumerable, Ownable {
    using ECDSA for bytes32;

    uint256 private _currentTokenId;

    struct Account {
        mapping(address => mapping(uint256 => uint256)) walletChainLimits;
        address[] walletList;
        address[] managers;
        mapping(address => mapping(uint256 => bool)) autogas;
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

    event ManagerAdded(uint256 indexed nftId, address manager);
    event ManagerRemoved(uint256 indexed nftId, address manager);
    event WalletApproved(uint256 indexed nftId, address wallet);
    event WalletRemoved(uint256 indexed nftId, address wallet);
    event ChainEnabled(uint256 indexed nftId, uint256 chainId);
    event ChainDisabled(uint256 indexed nftId, uint256 chainId);
    event WalletLimitSet(uint256 indexed nftId, address wallet, uint256 limit);
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

    function isManagerOrOwner(uint256 nftId, address addr) public view returns (bool) {
        return ownerOf(nftId) == addr || isManager(nftId, addr);
    }

    function isManager(uint256 nftId, address addr) public view returns (bool) {
        Account storage account = _accounts[nftId];
        for (uint i = 0; i < account.managers.length; i++) {
            if (account.managers[i] == addr) {
                return true;
            }
        }
        return false;
    }

    function addManager(uint256 nftId, address manager) external {
        require(ownerOf(nftId) == msg.sender, "Not the token owner");
        require(!isManager(nftId, manager), "Already a manager");
        _accounts[nftId].managers.push(manager);
        emit ManagerAdded(nftId, manager);
    }

    function removeManager(uint256 nftId, address manager) external {
        require(ownerOf(nftId) == msg.sender, "Not the token owner");
        Account storage account = _accounts[nftId];
        for (uint i = 0; i < account.managers.length; i++) {
            if (account.managers[i] == manager) {
                account.managers[i] = account.managers[account.managers.length - 1];
                account.managers.pop();
                emit ManagerRemoved(nftId, manager);
                return;
            }
        }
        revert("Manager not found");
    }

    function setHigherLimit(uint256 nftId, address wallet, uint256 chainId, uint256 newLimit) external {
        require(isManagerOrOwner(nftId, msg.sender), "Not authorized");
        if (!isWalletAdded(nftId, wallet)) {
            _accounts[nftId].walletList.push(wallet);
        }
        _setHigherLimit(nftId, wallet, chainId, newLimit);
    }

    function setHigherBulkLimits(
        uint256 nftId,
        address wallet,
        uint256[] memory chainIds,
        uint256[] memory newLimits,
        bool[] memory autogas
    ) external {
        require(isManagerOrOwner(nftId, msg.sender), "Not authorized");
        if (!isWalletAdded(nftId, wallet)) {
            _accounts[nftId].walletList.push(wallet);
        }
        require(chainIds.length == newLimits.length && newLimits.length == autogas.length, "Lengths of lists should match");
        for (uint256 i = 0; i < chainIds.length; i++) {
            _setHigherLimit(nftId, wallet, chainIds[i], newLimits[i]);
            _accounts[nftId].autogas[wallet][chainIds[i]] = autogas[i];
        }
    }

    function _setHigherLimit(uint256 nftId, address wallet, uint256 chainId, uint256 newLimit) internal {
        require(approvedChains[chainId], "Chain not approved by the issuer");
        uint256 currentLimit = _accounts[nftId].walletChainLimits[wallet][chainId];
        require(newLimit >= currentLimit, "New limit must be higher than current limit");
        _accounts[nftId].walletChainLimits[wallet][chainId] = newLimit;
    }

    function setLowerLimit(
        uint256 nftId,
        address wallet,
        uint256 chainId,
        uint256 newLimit,
        uint256 timestamp,
        uint256 nonce, 
        bytes memory signature
    ) external {
        require(isManagerOrOwner(nftId, msg.sender), "Not authorized");
        require(isWalletAdded(nftId, wallet), "Wallet not added");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(nonce == lowerLimitNonces[nftId], "Invalid limit change nonce");

        bytes32 messageHash = keccak256(abi.encodePacked(nftId, wallet, chainId, newLimit, timestamp, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuer, "Invalid signature");

        _accounts[nftId].walletChainLimits[wallet][chainId] = newLimit;
        lowerLimitNonces[nftId]++;
    }

    function setLowerBulkLimits(
        uint256 nftId,
        address wallet,
        uint256[] memory chainIds,
        uint256[] memory newLimits,
        uint256 timestamp,
        uint256 nonce,
        bytes memory signature
    ) external {
        require(isManagerOrOwner(nftId, msg.sender), "Not authorized");
        require(isWalletAdded(nftId, wallet), "Wallet not added");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(chainIds.length == newLimits.length, "Limits leagth should match the chain List length");
        require(nonce == lowerLimitNonces[nftId], "Invalid limit change nonce");

        bytes32 messageHash = keccak256(abi.encode(nftId, wallet, chainIds, newLimits, timestamp, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuer, "Invalid signature");

        for (uint256 i = 0; i < chainIds.length; i++) {
            _accounts[nftId].walletChainLimits[wallet][chainIds[i]] = newLimits[i];
        }
        lowerLimitNonces[nftId]++;
    }

    function resetWalletChainLimits(
        uint256 nftId,
        address wallet,
        uint256 timestamp,
        uint256 nonce,
        bytes memory signature
    ) public {
        require(isManagerOrOwner(nftId, msg.sender), "Not authorized");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(nonce == lowerLimitNonces[nftId], "Invalid limit change nonce");

        bytes32 messageHash = keccak256(abi.encodePacked(nftId, wallet, timestamp, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuer, "Invalid signature");

        for (uint i = 0; i < chainList.length; i++) {
            delete _accounts[nftId].walletChainLimits[wallet][chainList[i]];
        }
        lowerLimitNonces[nftId]++;
    }

    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function setMintPrice(uint256 _mintPrice) external onlyIssuer {
        mintPrice = _mintPrice;
    }

    function setMaxNFTs(uint256 _maxNFTs) external onlyIssuer {
        require(_maxNFTs >= _currentTokenId, "Cannot set max lower than current total");
        maxNFTs = _maxNFTs;
    }

    function withdrawFunds() external onlyIssuer {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function setExtraLimit(uint256 nftId, uint256 _extraLimit) external onlyIssuer {
        require(_extraLimit > _accounts[nftId].extraLimit);
        _accounts[nftId].extraLimit = _extraLimit;
    }

    function setBulkExtraLimits(uint256[] calldata nftIds, uint256 _extraLimit) external onlyIssuer {
        for (uint256 i = 0; i < nftIds.length; i++) {
            require(_extraLimit > _accounts[nftIds[i]].extraLimit, "New limit must be higher than old");
            _accounts[nftIds[i]].extraLimit = _extraLimit;
        }
    }

    function setDefaultExtraLimit(uint256 _extraLimit) external onlyIssuer {
        defaultExtraLimit = _extraLimit;
    }

    function setNewIssuer(address newIssuer) external onlyIssuer {
        issuer = newIssuer;
    }

    function getManagers(uint256 nftId) external view returns (address[] memory) {
        return _accounts[nftId].managers;
    }

    function getAutogasConfig(uint256 nftId, address wallet) external view returns (bool[] memory) {
        uint256 chainCount = chainList.length;
        bool[] memory autogasList = new bool[](chainCount);
        
        for (uint i = 0; i < chainCount; i++) {
            autogasList[i] = _accounts[nftId].autogas[wallet][chainList[i]];
        }
        
        return autogasList;
    }

    function getExtraLimit(uint256 nftId) external view returns (uint256) {
        return _accounts[nftId].extraLimit;
    }
    
    function getWallets(uint256 nftId) external view returns (address[] memory) {
        return _accounts[nftId].walletList;
    }

    function getLimitsConfig(uint256 nftId, address wallet) external view returns (uint256[] memory) {
        uint256 chainCount = chainList.length;
        uint256[] memory limitsList = new uint256[](chainCount);
        
        for (uint i = 0; i < chainCount; i++) {
            limitsList[i] = _accounts[nftId].walletChainLimits[wallet][chainList[i]];
        }
        
        return limitsList;
    }

    function isWalletAdded(uint256 nftId, address wallet) public view returns (bool) {
        address[] memory wallets = _accounts[nftId].walletList;
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

    function getWalletChainLimit(uint256 nftId, address wallet, uint256 chainId) external view returns (uint256) {
        return _accounts[nftId].walletChainLimits[wallet][chainId];
    }

    function _getWalletChainLimit(uint256 nftId, address wallet, uint256 chainId) internal view returns (uint256) {
        return _accounts[nftId].walletChainLimits[wallet][chainId];
    }

    function getWalletsWithLimitChain(uint256 nftId, uint256 chainId) external view returns (address[] memory) {
        // First, count the number of wallets with limits
        uint256 count = 0;
        for (uint256 i = 0; i < _accounts[nftId].walletList.length; i++) {
            if (_getWalletChainLimit(nftId, _accounts[nftId].walletList[i], chainId) > 0) {
                count++;
            }
        }
    
        // Create a fixed-size array with the correct length
        address[] memory walletsWithLimits = new address[](count);
    
        // Fill the array
        uint256 index = 0;
        for (uint256 i = 0; i < _accounts[nftId].walletList.length; i++) {
            if (_getWalletChainLimit(nftId, _accounts[nftId].walletList[i], chainId) > 0) {
                walletsWithLimits[index] = _accounts[nftId].walletList[i];
                index++;
            }
        }
    
        return walletsWithLimits;
    }

    function _update(address to, uint256 nftId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, nftId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
