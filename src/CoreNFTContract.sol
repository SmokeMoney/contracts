// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {console2} from "forge-std/src/Test.sol"; // TODO REMOVE AFDTRER TEST

contract CoreNFTContract is EIP712, ERC721, ERC721Enumerable, Ownable {
    using ECDSA for bytes32;
    using Strings for uint256;

    uint256 private _currentTokenId;

    struct GNFTWallet {
        uint256 gNFT;
        bytes32 gWallet;
    }

    struct Account {
        mapping(bytes32 => mapping(uint256 => uint256)) walletChainLimits;
        bytes32[] walletList;
        address[] managers;
        mapping(bytes32 => mapping(uint256 => bool)) autogas;
        uint256 nativeCredit;
        uint256 gNFTCount;
        bytes32[] pWalletList;
        GNFTWallet[] gNFTList;
    }

    bytes32 private constant SET_LOWER_LIMIT_TYPEHASH = keccak256(
        "SetLowerLimit(uint256 nftId,bytes32 wallet,uint256 chainId,uint256 newLimit,uint256 timestamp,uint256 nonce)"
    );

    bytes32 private constant SET_LOWER_BULK_LIMITS_TYPEHASH = keccak256(
        "SetLowerBulkLimits(uint256 nftId,bytes32 wallet,uint256[] chainIds,uint256[] newLimits,uint256 timestamp,uint256 nonce)"
    );

    bytes32 private constant RESET_WALLET_CHAIN_LIMITS_TYPEHASH =
        keccak256("ResetWalletChainLimits(uint256 nftId,bytes32 wallet,uint256 timestamp,uint256 nonce)");

    bytes32 private constant ADD_G_WALLET_TYPEHASH =
        keccak256("AddGWallet(uint256 nftId,bytes32 wallet,uint256 timestamp,uint256 gNFTCount)");

    bytes32 private constant CONNECT_G_WALLET_TYPEHASH =
        keccak256("ConnectGWallet(uint256 nftId,uint256 gNFTId,bytes32 wallet,bytes32 gWallet)");

    address[] private _ownershipHistory;
    mapping(uint256 => uint256) private _referrers;
    mapping(uint256 => Account) private _accounts;
    mapping(uint256 => uint256) private _gNFTMapping; // gNFT => NFT
    uint256 public mintPrice;
    uint256 public maxNFTs;
    uint256 public defaultNativeCredit;
    mapping(uint256 => bool) public approvedChains;
    uint256[] public chainList;
    mapping(uint256 => uint256) public lowerLimitNonces;
    string private _baseTokenURI;

    uint256 public constant LTV_RATIO = 9000; // 90% LTV ratio
    uint256 public constant LIQ_THRESHOLD = 9500; // 95% LTV ratio
    uint256 public constant SIGNATURE_VALIDITY = 5 minutes;
    uint256 public constant TOTAL_SUPPLY = 15792089237316195423570985008687907853269984665640564039457584007913129639935;

    event ManagerAdded(uint256 indexed nftId, address manager);
    event ManagerRemoved(uint256 indexed nftId, address manager);
    event WalletApproved(uint256 indexed nftId, bytes32 wallet);
    event WalletRemoved(uint256 indexed nftId, bytes32 wallet);
    event ChainEnabled(uint256 indexed nftId, uint256 chainId);
    event ChainDisabled(uint256 indexed nftId, uint256 chainId);
    event WalletLimitSet(uint256 indexed nftId, bytes32 wallet, uint256 limit);
    event ChainAdded(uint256 chainId);
    event ChainApproved(uint256 chainId);
    event ChainDisapproved(uint256 chainId);
    event WalletConnected(uint256 nftId, uint256 gNFTId, bytes32 wallet, bytes32 gWallet);

    constructor(string memory name, string memory symbol, address _owner, uint256 _mintPrice, uint256 _maxNFTs)
        ERC721(name, symbol)
        Ownable(_owner)
        EIP712("CoreNFTContract", "1") // @attackVector I don't have salt for my 712 implementation, is this a concern?
    {
        mintPrice = _mintPrice;
        maxNFTs = _maxNFTs;
    }

    modifier onlyNFTOwner(uint256 nftId) {
        require(ownerOf(nftId) == msg.sender, "Not the NFT owner");
        _;
    }

    function mint(uint256 referrer) external payable returns (uint256) {
        require(msg.value >= mintPrice, "Insufficient payment");
        require(_currentTokenId <= maxNFTs, "Max NFTs minted");

        _currentTokenId++;
        uint256 newTokenId = _currentTokenId;
        _accounts[newTokenId].nativeCredit = defaultNativeCredit;
        _referrers[newTokenId] = referrer;
        _safeMint(msg.sender, newTokenId);
        return newTokenId;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(tokenId > 0 && tokenId <= _currentTokenId, "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function approveChain(uint256 chainId) external onlyOwner {
        if (!isChainInList(chainId)) {
            chainList.push(chainId);
            emit ChainAdded(chainId);
        }
        approvedChains[chainId] = true;
        emit ChainApproved(chainId);
    }

    function disapproveChain(uint256 chainId) external onlyOwner {
        approvedChains[chainId] = false;
        emit ChainDisapproved(chainId);
    }

    function isChainInList(uint256 chainId) public view returns (bool) {
        for (uint256 i = 0; i < chainList.length; i++) {
            if (chainList[i] == chainId) {
                return true;
            }
        }
        return false;
    }

    function setHigherLimit(uint256 nftId, bytes32 wallet, uint256 chainId, uint256 newLimit)
        external
        onlyNFTOwner(nftId)
    {
        if (!isWalletAdded(nftId, wallet)) {
            _accounts[nftId].walletList.push(wallet);
        }
        _setHigherLimit(nftId, wallet, chainId, newLimit);
    }

    function setHigherBulkLimits(
        uint256 nftId,
        bytes32 wallet,
        uint256[] memory chainIds,
        uint256[] memory newLimits,
        bool[] memory autogas
    ) external onlyNFTOwner(nftId) {
        if (!isWalletAdded(nftId, wallet)) {
            _accounts[nftId].walletList.push(wallet);
        }
        require(
            chainIds.length == newLimits.length && newLimits.length == autogas.length, "Lengths of lists should match"
        );
        for (uint256 i = 0; i < chainIds.length; i++) {
            _setHigherLimit(nftId, wallet, chainIds[i], newLimits[i]);
            _accounts[nftId].autogas[wallet][chainIds[i]] = autogas[i];
        }
    }

    function _setHigherLimit(uint256 nftId, bytes32 wallet, uint256 chainId, uint256 newLimit) internal {
        require(approvedChains[chainId], "Chain not approved by the issuer");
        uint256 currentLimit = _accounts[nftId].walletChainLimits[wallet][chainId];
        require(newLimit >= currentLimit, "New limit must be higher than current limit");
        _accounts[nftId].walletChainLimits[wallet][chainId] = newLimit;
    }

    function setLowerLimit(
        uint256 nftId,
        bytes32 wallet,
        uint256 chainId,
        uint256 newLimit,
        uint256 timestamp,
        uint256 nonce,
        bytes memory signature
    ) external onlyNFTOwner(nftId) {
        require(isWalletAdded(nftId, wallet), "Wallet not added");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(nonce == lowerLimitNonces[nftId], "Invalid limit change nonce");

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(SET_LOWER_LIMIT_TYPEHASH, nftId, wallet, chainId, newLimit, timestamp, nonce))
        );

        _verifySignature(digest, signature);

        _accounts[nftId].walletChainLimits[wallet][chainId] = newLimit;
        lowerLimitNonces[nftId]++;
    }

    function setLowerBulkLimits(
        uint256 nftId,
        bytes32 wallet,
        uint256[] memory chainIds,
        uint256[] memory newLimits,
        uint256 timestamp,
        uint256 nonce,
        bytes memory signature
    ) external onlyNFTOwner(nftId) {
        require(isWalletAdded(nftId, wallet), "Wallet not added");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(chainIds.length == newLimits.length, "Limits length should match the chain List length");
        require(nonce == lowerLimitNonces[nftId], "Invalid limit change nonce");

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    SET_LOWER_BULK_LIMITS_TYPEHASH,
                    nftId,
                    wallet,
                    keccak256(abi.encodePacked(chainIds)),
                    keccak256(abi.encodePacked(newLimits)),
                    timestamp,
                    nonce
                )
            )
        );

        _verifySignature(digest, signature);

        for (uint256 i = 0; i < chainIds.length; i++) {
            _accounts[nftId].walletChainLimits[wallet][chainIds[i]] = newLimits[i];
        }
        lowerLimitNonces[nftId]++;
    }

    function resetWalletChainLimits(
        uint256 nftId,
        bytes32 wallet,
        uint256 timestamp,
        uint256 nonce,
        bytes memory signature
    ) external onlyNFTOwner(nftId) {
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(nonce == lowerLimitNonces[nftId], "Invalid limit change nonce");

        bytes32 digest =
            _hashTypedDataV4(keccak256(abi.encode(RESET_WALLET_CHAIN_LIMITS_TYPEHASH, nftId, wallet, timestamp, nonce)));

        _verifySignature(digest, signature);

        for (uint256 i = 0; i < chainList.length; i++) {
            delete _accounts[nftId].walletChainLimits[wallet][chainList[i]];
        }
        lowerLimitNonces[nftId]++;
    }

    function addGWallet(uint256 nftId, bytes32 wallet, uint256 timestamp, uint256 gNFTCount, bytes memory signature)
        external
        onlyNFTOwner(nftId)
    {
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(!isWalletAdded(nftId, wallet), "Wallet already added");

        bytes32 digest =
            _hashTypedDataV4(keccak256(abi.encode(ADD_G_WALLET_TYPEHASH, nftId, wallet, timestamp, gNFTCount)));

        _verifySignature(digest, signature);

        _accounts[nftId].walletList.push(wallet);
        _accounts[nftId].pWalletList.push(wallet);
        _accounts[nftId].gNFTCount++;
    }

    function connectGWallet(uint256 nftId, uint256 gNFTId, bytes32 wallet, bytes32 gWallet, bytes memory signature)
        external
        onlyNFTOwner(nftId)
    {
        bytes32 digest =
            _hashTypedDataV4(keccak256(abi.encode(CONNECT_G_WALLET_TYPEHASH, nftId, gNFTId, wallet, gWallet)));

        require(_verifyHistIssuerSignature(digest, signature), "Invalid issuer signature");

        // Remove the specific wallet from the list
        bool found = false;
        uint256 walletIndex;
        for (uint256 i = 0; i < _accounts[nftId].pWalletList.length; i++) {
            if (_accounts[nftId].pWalletList[i] == wallet) {
                walletIndex = i;
                found = true;
                break;
            }
        }
        require(found, "Wallet not found in the list");

        // Move the last element to the position of the wallet to be removed
        _accounts[nftId].pWalletList[walletIndex] =
            _accounts[nftId].pWalletList[_accounts[nftId].pWalletList.length - 1];
        // Remove the last element
        _accounts[nftId].pWalletList.pop();

        // Add the new gWallet
        _accounts[nftId].walletList.push(gWallet);
        _accounts[nftId].gNFTList.push(GNFTWallet({gNFT: gNFTId, gWallet: gWallet}));
        require(_gNFTMapping[gNFTId] == 0, "gNFT already used");
        _gNFTMapping[gNFTId] = nftId;

        for (uint256 i = 0; i < chainList.length; i++) {
            _accounts[nftId].walletChainLimits[gWallet][chainList[i]] =
                _accounts[nftId].walletChainLimits[wallet][chainList[i]];
            delete _accounts[nftId].walletChainLimits[wallet][chainList[i]];
        }

        emit WalletConnected(nftId, gNFTId, wallet, gWallet);
    }

    function _verifyHistIssuerSignature(bytes32 digest, bytes memory signature) internal view returns (bool) {
        for (uint256 i = 0; i < _ownershipHistory.length; i++) {
            if (SignatureChecker.isValidSignatureNow(_ownershipHistory[i], digest, signature)) {
                return true;
            }
        }
        return false;
    }

    function _verifySignature(bytes32 digest, bytes memory signature) internal view {
        require(SignatureChecker.isValidSignatureNow(owner(), digest, signature), "Invalid signature from issuer");
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

    function setNativeCredit(uint256 nftId, uint256 _nativeCredit) external onlyOwner {
        require(_nativeCredit > _accounts[nftId].nativeCredit);
        _accounts[nftId].nativeCredit = _nativeCredit;
    }

    function setBulkNativeCredits(uint256[] calldata nftIds, uint256 _nativeCredit) external onlyOwner {
        for (uint256 i = 0; i < nftIds.length; i++) {
            require(_nativeCredit > _accounts[nftIds[i]].nativeCredit, "New limit must be higher than old");
            _accounts[nftIds[i]].nativeCredit = _nativeCredit;
        }
    }

    function setDefaultNativeCredit(uint256 _nativeCredit) external onlyOwner {
        defaultNativeCredit = _nativeCredit;
    }

    function getAutogasConfig(uint256 nftId, bytes32 wallet) external view returns (bool[] memory) {
        uint256 chainCount = chainList.length;
        bool[] memory autogasList = new bool[](chainCount);

        for (uint256 i = 0; i < chainCount; i++) {
            autogasList[i] = _accounts[nftId].autogas[wallet][chainList[i]];
        }

        return autogasList;
    }

    function getNativeCredit(uint256 nftId) external view returns (uint256) {
        return _accounts[nftId].nativeCredit;
    }

    function getReferrer(uint256 nftId) external view returns (uint256) {
        return _referrers[nftId];
    }

    function getWallets(uint256 nftId) external view returns (bytes32[] memory) {
        return _accounts[nftId].walletList;
    }

    function getGNFTList(uint256 nftId) external view returns (uint256[] memory) {
        uint256 count = _accounts[nftId].gNFTCount;
        uint256[] memory list = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            list[i] = _accounts[nftId].gNFTList[i].gNFT;
        }
        return list;
    }

    function getGWallet(uint256 gNFT) external view returns (bytes32) {
        uint256 nftId = _gNFTMapping[gNFT];
        for (uint256 i = 0; i < _accounts[nftId].gNFTCount; i++) {
            if (_accounts[nftId].gNFTList[i].gNFT == gNFT) {
                return _accounts[nftId].gNFTList[i].gWallet;
            }
        }
        return bytes32(0);
    }

    function getTotalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQ_THRESHOLD;
    }

    function getLTV() external pure returns (uint256) {
        return LTV_RATIO;
    }

    function getLimitsConfig(uint256 nftId, bytes32 wallet) external view returns (uint256[] memory) {
        uint256 chainCount = chainList.length;
        uint256[] memory limitsList = new uint256[](chainCount);

        for (uint256 i = 0; i < chainCount; i++) {
            limitsList[i] = _accounts[nftId].walletChainLimits[wallet][chainList[i]];
        }

        return limitsList;
    }

    function isWalletAdded(uint256 nftId, bytes32 wallet) public view returns (bool) {
        bytes32[] memory wallets = _accounts[nftId].walletList;
        for (uint256 i = 0; i < wallets.length; i++) {
            if (wallets[i] == wallet) {
                return true;
            }
        }
        wallets = _accounts[nftId].pWalletList;
        for (uint256 i = 0; i < wallets.length; i++) {
            if (wallets[i] == wallet) {
                return true;
            }
        }
        return false;
    }

    function getChainList() external view returns (uint256[] memory) {
        return chainList;
    }

    function getGNFTCount(uint256 nftId) external view returns (uint256) {
        return _accounts[nftId].gNFTCount;
    }

    function getWalletChainLimit(uint256 nftId, bytes32 wallet, uint256 chainId) external view returns (uint256) {
        return _accounts[nftId].walletChainLimits[wallet][chainId];
    }

    function _getWalletChainLimit(uint256 nftId, bytes32 wallet, uint256 chainId) internal view returns (uint256) {
        return _accounts[nftId].walletChainLimits[wallet][chainId];
    }

    function getWalletsWithLimitChain(uint256 nftId, uint256 chainId) external view returns (bytes32[] memory) {
        // First, count the number of wallets with limits
        uint256 count = 0;
        for (uint256 i = 0; i < _accounts[nftId].walletList.length; i++) {
            if (_getWalletChainLimit(nftId, _accounts[nftId].walletList[i], chainId) > 0) {
                count++;
            }
        }

        // Create a fixed-size array with the correct length
        bytes32[] memory walletsWithLimits = new bytes32[](count);

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

    function getPWalletsTotalLimit(uint256 nftId) external view returns (uint256) {
        uint256 totalPWalletLimit; // placeholder wallets limits
        for (uint256 i = 0; i < _accounts[nftId].pWalletList.length; i++) {
            for (uint256 j = 0; j < chainList.length; j++) {
                totalPWalletLimit += _getWalletChainLimit(nftId, _accounts[nftId].pWalletList[i], chainList[j]);
            }
        }
        return totalPWalletLimit;
    }

    function transferOwnership(address newOwner) public virtual override onlyOwner {
        address oldOwner = owner();
        require(_ownershipHistory.length < 100, "max limit reached"); // else the owner can grieve the gNFT holders by making it really expensive to connect
        super.transferOwnership(newOwner);
        _ownershipHistory.push(newOwner);
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function _update(address to, uint256 nftId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, nftId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
