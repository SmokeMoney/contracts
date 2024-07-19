// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";

interface IDepositContract {
    function executeWithdrawal(address user, address token, uint256 nftId, uint256 amount) external;
}

contract CrossChainLendingAccount is ERC721, ERC721Enumerable, Ownable, OApp, OAppOptionsType3 {
    using ECDSA for bytes32;

    uint256 private _currentTokenId;

    struct Account {
        mapping(address => bool) approvedWallets;
        mapping(uint256 => bool) enabledChains;
        mapping(address => uint256) walletLimits;
        address[] walletList;
        address[] managers;
    }

    mapping(uint256 => Account) private _accounts;
    address public issuer;
    mapping(uint256 => bool) public approvedChains;
    uint256 public immutable adminChainId;
    mapping(uint256 => uint256) public withdrawalNonces; // nftId => chainId => nonce
    mapping(uint256 => IDepositContract) public depositContracts;

    uint256 public constant SIGNATURE_VALIDITY = 5 minutes;
    string public data = "Nothing received yet";

    event ManagerAdded(uint256 indexed tokenId, address manager);
    event ManagerRemoved(uint256 indexed tokenId, address manager);
    event WalletApproved(uint256 indexed tokenId, address wallet);
    event WalletRemoved(uint256 indexed tokenId, address wallet);
    event ChainEnabled(uint256 indexed tokenId, uint256 chainId);
    event ChainDisabled(uint256 indexed tokenId, uint256 chainId);
    event WalletLimitSet(uint256 indexed tokenId, address wallet, uint256 limit);
    event ChainApproved(uint256 chainId);
    event ChainDisapproved(uint256 chainId);
    event Withdrawn(uint256 indexed nftId, address indexed token, uint256 amount, uint32 targetChainId);
    event ForcedWithdrawalExecuted(uint256 indexed nftId, address indexed token, uint256 amount, uint32 targetChainId);
    event CrossChainWithdrawalInitiated(uint256 indexed nftId, address indexed token, uint256 amount, uint32 targetChainId);

    constructor(string memory name, string memory symbol, address _issuer, address _endpoint, address _owner, uint256 _adminChainId) 
        ERC721(name, symbol) 
        OApp(_endpoint, _owner)
        Ownable(msg.sender)
    {
        issuer = _issuer;
        adminChainId = _adminChainId;
    }

    modifier onlyIssuer() {
        require(msg.sender == issuer, "Not the issuer");
        _;
    }

    function mint() external returns (uint256) {
        _currentTokenId++;
        uint256 newTokenId = _currentTokenId;
        withdrawalNonces[newTokenId] = 1;
        _safeMint(msg.sender, newTokenId);
        return newTokenId;
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

    function approveWallet(uint256 tokenId, address wallet) external {
        require(ownerOf(tokenId) == msg.sender, "Not the token owner");
        require(!_accounts[tokenId].approvedWallets[wallet], "Wallet already approved");
        _accounts[tokenId].approvedWallets[wallet] = true;
        _accounts[tokenId].walletList.push(wallet);
        emit WalletApproved(tokenId, wallet);
    }

    function removeWallet(uint256 tokenId, address wallet) external onlyIssuer {
        require(_accounts[tokenId].approvedWallets[wallet], "Wallet not approved");
        _accounts[tokenId].approvedWallets[wallet] = false;
        for (uint i = 0; i < _accounts[tokenId].walletList.length; i++) {
            if (_accounts[tokenId].walletList[i] == wallet) {
                _accounts[tokenId].walletList[i] = _accounts[tokenId].walletList[_accounts[tokenId].walletList.length - 1];
                _accounts[tokenId].walletList.pop();
                break;
            }
        }
        emit WalletRemoved(tokenId, wallet);
    }

    function approveChain(uint256 chainId) external onlyIssuer {
        approvedChains[chainId] = true;
        emit ChainApproved(chainId);
    }

    function disapproveChain(uint256 chainId) external onlyIssuer {
        approvedChains[chainId] = false;
        emit ChainDisapproved(chainId);
    }

    function enableChain(uint256 tokenId, uint256 chainId) external {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        require(approvedChains[chainId], "Chain not approved by issuer");
        _accounts[tokenId].enabledChains[chainId] = true;
        emit ChainEnabled(tokenId, chainId);
    }

    function disableChain(uint256 tokenId, uint256 chainId) external {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        _accounts[tokenId].enabledChains[chainId] = false;
        emit ChainDisabled(tokenId, chainId);
    }

    function setWalletLimit(uint256 tokenId, address wallet, uint256 limit) external {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        require(_accounts[tokenId].approvedWallets[wallet], "Wallet not approved");
        _accounts[tokenId].walletLimits[wallet] = limit;
        emit WalletLimitSet(tokenId, wallet, limit);
    }

    function withdraw(
        address token,
        uint256 nftId,
        uint256 amount,
        uint32 targetChainId,
        uint256 timestamp,
        uint256 nonce,
        bytes memory signature,
        bytes calldata _extraOptions
    ) external payable {
        require(isManagerOrOwner(nftId, msg.sender), "Not authorized");
        require(approvedChains[targetChainId], "Chain not   supported");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(nonce == withdrawalNonces[nftId], "Invalid withdraw nonce");

        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, token, nftId, amount, targetChainId, timestamp, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuer, "Invalid withdraw signature");

        _executeWithdrawal(msg.sender, token, nftId, amount, targetChainId, _extraOptions);
    }

    function forcedWithdrawal(
        uint256 nftId,
        address token,
        uint256 amount,
        uint32 targetChainId,
        bytes[] calldata chainProofs,
        bytes calldata _extraOptions
    ) external {
        require(isManagerOrOwner(nftId, msg.sender), "Not authorized");
        require(approvedChains[targetChainId], "Chain not supported");
        require(chainProofs.length > 0, "No chain proofs provided");

        uint256 totalCollateral = 0;
        uint256 totalBorrowed = 0;

        // for (uint256 i = 0; i < chainProofs.length; i++) {
        //     IDepositContract depositContract = depositContracts[targetChainId];
        //     require(address(depositContract) != address(0), "Deposit contract not set for this chain");

        //     (uint256 chainId, uint256 collateral, uint256 borrowed) = depositContract.verifyChainProof(nftId, chainProofs[i]);
        //     require(approvedChains[chainId], "Unsupported chain in proof");
        //     require(_accounts[nftId].enabledChains[chainId], "Chain not enabled for this NFT");
        //     totalCollateral += collateral;
        //     totalBorrowed += borrowed;
        // }

        require(totalCollateral >= totalBorrowed + amount, "Insufficient collateral for withdrawal");

        _executeWithdrawal(msg.sender, token, nftId, amount, targetChainId, _extraOptions);

        emit ForcedWithdrawalExecuted(nftId, token, amount, targetChainId);
    }

    function _executeWithdrawal(address user, address token, uint256 nftId, uint256 amount, uint32 targetChainId, bytes calldata _extraOptions) internal {
        if (targetChainId == adminChainId) {
            IDepositContract depositContract = depositContracts[targetChainId];
            require(address(depositContract) != address(0), "Deposit contract not set for this chain");
            depositContract.executeWithdrawal(user, token, nftId, amount);
            emit Withdrawn(nftId, token, amount, targetChainId);
        } else {
            _initiateCrossChainWithdrawal(user, token, nftId, amount, targetChainId, _extraOptions);
        }
    }

    function _initiateCrossChainWithdrawal(address user, address token, uint256 nftId, uint256 amount, uint32 targetChainId, bytes calldata _extraOptions) internal {
        // require(approvedChains[targetChainId], "Target chain not approved"); NO NEED TO CHECK THIS. IT DOESN"T HAVE TO BE APPROVED
        
        // Prepare the payload for the cross-chain message
        bytes memory payload = abi.encode(
            user,
            token,
            nftId,
            amount,
            withdrawalNonces[nftId]
        );

        _lzSend(
            targetChainId,
            payload,
            // encodeMessage(_message, _msgType, _extraReturnOptions),
            _extraOptions,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            payable(msg.sender) 
        );
        // Increment the nonce
        withdrawalNonces[nftId]++;

        emit CrossChainWithdrawalInitiated(nftId, token, amount, targetChainId);
    }

    function _lzReceive(
        Origin calldata _origin, // struct containing info about the message sender
        bytes32 _guid, // global packet identifier
        bytes calldata payload, // encoded message payload being received
        address _executor, // the Executor address.
        bytes calldata _extraData // arbitrary data appended by the Executor
        ) internal override {
            data = abi.decode(payload, (string)); // your logic here
    }

        /**
     * @notice Returns the estimated messaging fee for a given message.
     * @param targetChainId Destination endpoint ID where the message will be sent.
     * @param _msgType The type of message being sent.
     * @param user Input needed to calculate the message payload.
     * @param token Input needed to calculate the message payload.
     * @param nftId Input needed to calculate the message payload.
     * @param amount Input needed to calculate the message payload.
     * @param _extraOptions Gas options for sending the call (A -> B).
     * @param _payInLzToken Boolean flag indicating whether to pay in LZ token.
     * @return fee The estimated messaging fee.
     */
     function quote(
        uint32 targetChainId,
        uint16 _msgType,
        address user,
        address token, 
        uint256 nftId, 
        uint256 amount,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(
            user,
            token,
            nftId,
            amount,
            withdrawalNonces[nftId]
        );

        fee = _quote(targetChainId, payload, _extraOptions, _payInLzToken);
    }


    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function setDepositContract(uint256 chainId, address contractAddress) external onlyIssuer {
        depositContracts[chainId] = IDepositContract(contractAddress);
    }

    function getApprovedWallets(uint256 tokenId) external view returns (address[] memory) {
        return _accounts[tokenId].walletList;
    }

    function isWalletApproved(uint256 tokenId, address wallet) external view returns (bool) {
        return _accounts[tokenId].approvedWallets[wallet];
    }

    function isChainEnabled(uint256 tokenId, uint256 chainId) external view returns (bool) {
        return _accounts[tokenId].enabledChains[chainId];
    }

    function getWalletLimit(uint256 tokenId, address wallet) external view returns (uint256) {
        return _accounts[tokenId].walletLimits[wallet];
    }

    function getManagers(uint256 tokenId) external view returns (address[] memory) {
        return _accounts[tokenId].managers;
    }

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function getCurrentNonce(uint256 nftId) external view returns (uint256) {
        return withdrawalNonces[nftId];
    }

    // function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
    //     internal
    //     override(ERC721, ERC721Enumerable)
    // {
    //     super._beforeTokenTransfer(from, to, tokenId, batchSize);
    // }
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
