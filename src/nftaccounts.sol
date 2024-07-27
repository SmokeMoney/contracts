// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

interface IDepositContract {
    function executeWithdrawal(address user, address token, uint256 tokenId, uint256 amount) external;
}

contract CrossChainLendingAccount is ERC721, ERC721Enumerable, Ownable, OApp, OAppOptionsType3 {
    using ECDSA for bytes32;

    uint256 private _currentTokenId;
    uint256 private _currentAssembleId;

    struct Account {
        mapping(address => mapping(uint256 => uint256)) walletChainLimits;
        address[] walletList;
        address[] managers;
        mapping(address => bool) autogas;
        uint256 extraLimit;
    }

    struct AssemblePositions {
        uint256 nftId;
        mapping(uint256 => bool) chainReported;
        mapping(address => mapping(uint256 => uint256)) borrowPositions;
        mapping(uint256 => uint256) depositPositions;
        mapping(uint256 => uint256) wstETHDepositPositions;
        mapping(uint256 => address) wethAddresses;
        mapping(uint256 => address) wstETHAddresses;
        uint256 totalAvailableToWithdraw;
        bool isComplete;
        bool forWithdrawal;
        uint256 timestamp;
    }

    struct AssembleData {
        uint256 assembleId;
        uint256 nftId;
        uint256 depositAmount;
        uint256 wstETHDepositAmount;
        address wethAddress;
        address wstETHAddress;
    }
    
    struct WalletData {
        address[] wallets;
        uint256[] borrowAmounts;
        uint256[] interestAmounts;
    }

    IPyth pyth;
    mapping(uint256 => Account) private _accounts;
    mapping(uint256 => AssemblePositions) private _assemblePositions;
    address public issuer;
    mapping(uint256 => bool) public approvedChains;
    uint256[] public chainList;
    uint256 public immutable adminChainId;
    mapping(uint256 => uint256) public withdrawalNonces; // tokenId => nonce
    mapping(uint256 => uint256) public lowerLimitNonces; // tokenId => nonce
    mapping(uint256 => IDepositContract) public depositContracts;

    uint256 public constant SIGNATURE_VALIDITY = 5 minutes;
    string public data = "Nothing received yet";
    uint256 public constant LTV_RATIO = 90; // 90% LTV ratio
    uint256 public constant WSTETH_ETH_RATIO = 1100000000000000000; // 1.1 ETH per wstETH (example value)


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
    event Withdrawn(uint256 indexed tokenId, address indexed token, uint256 amount, uint32 targetChainId);
    event CrossChainWithdrawalInitiated(uint256 indexed tokenId, address indexed token, uint256 amount, uint32 targetChainId);
    event ChainPositionReported(uint256 indexed assembleId, uint256 chainId);
    event ForcedWithdrawalExecuted(uint256 indexed assembleId, address indexed token, uint256 amount, uint32 targetChainId);
    event AssemblePositionsCreated(uint256 indexed assembleId, uint256 indexed nftId, bool forWithdrawal);


    constructor(string memory name, string memory symbol, address _issuer, address _endpoint, address pythContract, address _owner, uint256 _adminChainId) 
        ERC721(name, symbol) 
        OApp(_endpoint, _owner)
        Ownable(msg.sender)
    {
        issuer = _issuer;
        adminChainId = _adminChainId;
        pyth = IPyth(pythContract);
    }

    modifier onlyIssuer() {
        require(msg.sender == issuer, "Not the issuer");
        _;
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
        approvedChains[chainId] = false; // the issuer can add a false flag to a non-approved chain, is this cool? 
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

    function mint() external returns (uint256) {
        _currentTokenId++;
        uint256 newTokenId = _currentTokenId;
        withdrawalNonces[newTokenId] = 1;
        _accounts[newTokenId].extraLimit = 5e15; //0.005
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
        require(chainIds.length == newLimits.length, "Limits leagth should match the chainList length");
        for (uint256 i = 0; i < chainIds.length; i++) {
            _setHigherLimit(tokenId, wallet, chainIds[i], newLimits[i]);
        }
        _accounts[tokenId].autogas[wallet] = autogas;
    }

    function _setHigherLimit(uint256 tokenId, address wallet, uint256 chainId, uint256 newLimit) internal {
        require(approvedChains[chainId], "Chain not approved by the issuer");
        uint256 currentLimit = _accounts[tokenId].walletChainLimits[wallet][chainId];
        require(newLimit > currentLimit, "New limit must be higher than current limit");
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
        require(chainIds.length == newLimits.length, "Limits leagth should match the chainList length");
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

    function withdraw(
        address token,
        uint256 tokenId,
        uint256 amount,
        uint32 targetChainId,
        uint256 timestamp,
        uint256 nonce,
        bytes memory signature,
        bytes calldata _extraOptions
    ) external payable {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(nonce == withdrawalNonces[tokenId], "Invalid withdraw nonce");

        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, token, tokenId, amount, targetChainId, timestamp, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuer, "Invalid withdraw signature");

        _executeWithdrawal(msg.sender, token, tokenId, amount, targetChainId, _extraOptions);
    }

    function _executeWithdrawal(address user, address token, uint256 tokenId, uint256 amount, uint32 targetChainId, bytes calldata _extraOptions) internal {
        if (targetChainId == adminChainId) {
            IDepositContract depositContract = depositContracts[targetChainId];
            require(address(depositContract) != address(0), "Deposit contract not set for this chain");
            depositContract.executeWithdrawal(user, token, tokenId, amount);
            emit Withdrawn(tokenId, token, amount, targetChainId);
            withdrawalNonces[tokenId]++;
        } else {
            _initiateCrossChainWithdrawal(user, token, tokenId, amount, targetChainId, _extraOptions);
        }
    }

    function _initiateCrossChainWithdrawal(address user, address token, uint256 tokenId, uint256 amount, uint32 targetChainId, bytes calldata _extraOptions) internal {
        
        // Prepare the payload for the cross-chain message
        bytes memory payload = abi.encode(
            user,
            token,
            tokenId,
            amount,
            withdrawalNonces[tokenId]
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
        withdrawalNonces[tokenId]++;

        emit CrossChainWithdrawalInitiated(tokenId, token, amount, targetChainId);
    }

    function createAssemblePositions(uint256 nftId, bool forWithdrawal, bytes[] calldata priceUpdate) external returns (uint256) {
        require(forWithdrawal == false || isManagerOrOwner(nftId, msg.sender), "Not authorized for withdrawal");
        
        _currentAssembleId++;
        uint256 assembleId = _currentAssembleId;

        uint fee = pyth.getUpdateFee(priceUpdate);
        pyth.updatePriceFeeds{ value: fee }(priceUpdate);
     
        bytes32 priceFeedIdETH = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace; // ETH/USD
        bytes32 priceFeedIdwstETH = 0x6df640f3b8963d8f8358f791f352b8364513f6ab1cca5ed3f1f7b5448980e784; // wstETH/USD
        PythStructs.Price memory ETHPrice = pyth.getPrice(priceFeedIdETH);
        PythStructs.Price memory wstETHPrice = pyth.getPrice(priceFeedIdwstETH);    
    
        AssemblePositions storage newAssemble = _assemblePositions[assembleId];
        newAssemble.nftId = nftId;
        newAssemble.forWithdrawal = forWithdrawal;
        newAssemble.timestamp = block.timestamp;

        emit AssemblePositionsCreated(assembleId, nftId, forWithdrawal);

        return assembleId;
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _payload,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        uint32 srcChainId = _origin.srcEid;
        uint256 assembleId = _setupAssemble(srcChainId, _payload);

        emit ChainPositionReported(assembleId, srcChainId);
    }

    function _setupAssemble(uint32 srcChainId, bytes calldata _payload) internal returns (uint256) {
        (AssembleData memory assembleData, WalletData memory walletData) = _decodeAssemblePayload(_payload);
    
        AssemblePositions storage assemble = _assemblePositions[assembleData.assembleId];
        
        require(assemble.nftId == assembleData.nftId, "Invalid NFT ID");
        require(!assemble.chainReported[srcChainId], "Chain already reported");
    
        assemble.chainReported[srcChainId] = true;
        assemble.depositPositions[srcChainId] = assembleData.depositAmount;
        assemble.wstETHDepositPositions[srcChainId] = assembleData.wstETHDepositAmount;
        assemble.wethAddresses[srcChainId] = assembleData.wethAddress;
        assemble.wstETHAddresses[srcChainId] = assembleData.wstETHAddress;
        
        for (uint256 i = 0; i < walletData.wallets.length; i++) {
            uint256 approvedLimit = _accounts[assembleData.nftId].walletChainLimits[walletData.wallets[i]][srcChainId];
            uint256 validBorrowAmount = approvedLimit == 0 ? 0 : (walletData.borrowAmounts[i] > approvedLimit ? approvedLimit + walletData.interestAmounts[i] : walletData.borrowAmounts[i] + walletData.interestAmounts[i]);
            assemble.borrowPositions[walletData.wallets[i]][srcChainId] = validBorrowAmount;
        }

        return assembleData.assembleId;
    }
    
    function _decodeAssemblePayload(bytes calldata _payload) private pure returns (AssembleData memory, WalletData memory) {
        (
            uint256 assembleId,
            uint256 nftId,
            uint256 depositAmount,
            uint256 wstETHDepositAmount,
            address wethAddress,
            address wstETHAddress,
            address[] memory wallets,
            uint256[] memory borrowAmounts,
            uint256[] memory interestAmounts
        ) = abi.decode(_payload, (uint256, uint256, uint256, uint256, address, address, address[], uint256[], uint256[]));
    
        return (
            AssembleData(assembleId, nftId, depositAmount, wstETHDepositAmount, wethAddress, wstETHAddress),
            WalletData(wallets, borrowAmounts, interestAmounts)
        );
    }
    
    function forcedWithdrawal(uint256 assembleId, address token, uint256[] memory amounts, uint32[] memory targetChainIds, bytes calldata _extraOptions) external {
        // @attackvector Can a malicious actor mess around with the token addresses and screw the protocol over? 
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        require(!assemble.isComplete, "Assemble already completed");
        require(assemble.forWithdrawal, "Not a withdrawal assemble");
        require(isManagerOrOwner(assemble.nftId, msg.sender), "Not authorized");

        // Verify all chains have reported TODO
        // _checkForUnaccountedWallets(uint256 assembleId);

        // Calculate total borrow and deposit positions
        (uint256 totalBorrowed, uint256 totalCollateral) = _calculateTotalPositions(assembleId);

        // Calculate total available to withdraw
        uint256 maxBorrow = totalCollateral * LTV_RATIO / 100;
        assemble.totalAvailableToWithdraw = maxBorrow > totalBorrowed ? maxBorrow - totalBorrowed : 0;
        // Execute withdrawals
        for (uint256 i = 0; i < amounts.length; i++) {
            // uint256 oracleMultiplier = token == assemble.wethAddresses[targetChainIds[i]] ? TODO
            require(assemble.totalAvailableToWithdraw >= amounts[i], "Insufficient funds to withdraw");
            assemble.totalAvailableToWithdraw -= amounts[i];

            _executeWithdrawal(msg.sender, token, assemble.nftId, amounts[i], targetChainIds[i], _extraOptions);

            emit ForcedWithdrawalExecuted(assembleId, token, amounts[i], targetChainIds[i]);
        }

        if (assemble.totalAvailableToWithdraw == 0) {
            assemble.isComplete = true;
        }
    }

    function _calculateTotalPositions(uint256 assembleId) internal view returns (uint256 totalBorrowed, uint256 totalDeposited) {
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        Account storage account = _accounts[assemble.nftId];

        for (uint256 j = 0; j < chainList.length; j++) {
            totalDeposited += assemble.depositPositions[chainList[j]];
            totalDeposited += assemble.wstETHDepositPositions[chainList[j]] * WSTETH_ETH_RATIO / 1e18;
            for (uint256 i = 0; i < account.walletList.length; i++) {
                address wallet = account.walletList[i];
                totalBorrowed += assemble.borrowPositions[wallet][chainList[j]];            
            }
        }
    }

        /**
     * @notice Returns the estimated messaging fee for a given message.
     * @param targetChainId Destination endpoint ID where the message will be sent.
     * @param _msgType The type of message being sent.
     * @param user Input needed to calculate the message payload.
     * @param token Input needed to calculate the message payload.
     * @param tokenId Input needed to calculate the message payload.
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
        uint256 tokenId, 
        uint256 amount,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(
            user,
            token,
            tokenId,
            amount,
            withdrawalNonces[tokenId]
        );

        fee = _quote(targetChainId, payload, _extraOptions, _payInLzToken);
    }

    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function setDepositContract(uint256 chainId, address contractAddress) external onlyIssuer {
        depositContracts[chainId] = IDepositContract(contractAddress);
    }

    function setExtraLimit(uint256 tokenId, uint256 extraLimit) external onlyIssuer {
        _accounts[tokenId].extraLimit = extraLimit;
    }

    function setAutogasForWallet(uint256 tokenId, address wallet, bool autogas) external {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        require(isWalletAdded(tokenId, wallet), "Wallet not added");
        _accounts[tokenId].autogas[wallet] = autogas;
    }

    function markAssembleComplete(uint256 assembleId, uint256 tokenId) external {
        require(isManagerOrOwner(tokenId, msg.sender), "Not authorized");
        AssemblePositions storage assemble = _assemblePositions[assembleId];
        require(assemble.nftId == tokenId, "Assemble doesn't belong to the caller");
        assemble.isComplete = true;
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

    function getChainsWithLimit(uint256 tokenId) external view returns (uint256[] memory chainsWithLImit) {
        for (uint256 i = 0; i < chainList.length; i++) {
            for (uint256 j = 0; j < _accounts[tokenId].walletList.length; j++) {
                if (_getWalletChainLimit(tokenId, _accounts[tokenId].walletList[j], chainList[i]) > 0) {
                    // asdf
                }
            }
        }
    }

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function getWithdrawNonce(uint256 tokenId) external view returns (uint256) {
        return withdrawalNonces[tokenId];
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

    function getWalletChainLimit(uint256 tokenId, address wallet, uint256 chainId) external view returns (uint256) {
        return _getWalletChainLimit(tokenId, wallet, chainId);
    }

    function _getWalletChainLimit(uint256 tokenId, address wallet, uint256 chainId) internal view returns (uint256) {
        return _accounts[tokenId].walletChainLimits[wallet][chainId];
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
