// SPDX-License-Identifier: CTOSL
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { console2 } from "forge-std/Test.sol"; // TODO REMOVE AFDTRER TEST

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function transfer(address dst, uint wad) external returns (bool);
}

contract SmokeSpendingContract is EIP712, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    struct BorrowPosition {
        uint256 amount;
        uint256 timestamp;
    }

    struct InterestRateChange {
        uint256 timestamp;
        uint256 rate;
    }

    struct IssuerData {
        address issuerAddress;
        uint256 borrowInterestRate;
        uint256 borrowFees;
        uint256 smokeFeesCollected;
        uint256 autogasThreshold;
        uint256 autogasRefillAmount;
        uint256 gasPriceThreshold;
        uint256 poolDeposited;
        mapping(uint256 => InterestRateChange[]) interestRateHistory;
        mapping(uint256 => mapping(address => BorrowPosition)) borrowPositions; // nftId => wallet => BorrowPosition  
        mapping(uint256 => uint256) borrowNonces; // nftId => nonce
        mapping(uint256 => address[]) borrowers; // nftId => array of borrower addresses 
    }

    struct BorrowParams {
        address issuerNFT;
        uint256 nftId;
        uint256 amount;
        uint256 timestamp;
        uint256 signatureValidity;
        uint256 nonce;
        bool weth;
        bool repayGas;
        address recipient;
    }
    
    bytes32 private constant BORROW_TYPEHASH = keccak256(
        "Borrow(address borrower,address issuerNFT,uint256 nftId,uint256 amount,uint256 timestamp,uint256 signatureValidity,uint256 nonce)"
    );

    IWETH public immutable WETH;
    
    mapping(address => IssuerData) public issuers; // issuer NFT Address -> issuerData

    uint256 public smokeFees;
    uint256 public smokeFeesMaxBps; // 1% maximum total fees
    uint256 public constant SECONDS_PER_YEAR = 31536000;
    uint256 public constant SIGNATURE_VALIDITY = 1 minutes;
    uint256 public constant REPORTED_POS_BLOCK = 20 minutes;
    address public spendingConfigContract;

    event Borrowed(address indexed issuerNFT, uint256 indexed nftId, address indexed wallet, uint256 amount);
    event BorrowedAndSent(address indexed issuerNFT, uint256 indexed nftId, address indexed wallet, uint256 amount, address recipient);
    event Repaid(address indexed issuerNFT, uint256 indexed nftId, address indexed wallet, uint256 amount);
    event AutogasTriggered(address indexed issuerNFT, uint256 indexed nftId, address indexed wallet, uint256 amount);
    event AutogasSpikeTriggered(address indexed issuerNFT, uint256 indexed nftId, address indexed wallet, uint256 amount);
    event PoolDeposited(address indexed issuerNFT, uint256 amount);
    event PoolWithdrawn(address indexed issuerNFT, uint256 amount);
    event BorrowFeesSet(address indexed issuerNFT, uint256 newFees);
    event InterestRateChanged(address indexed issuerNFT, uint256 newRate);
    event GasPriceThresholdChanged(address indexed issuerNFT, uint256 newThreshold);
    event IssuerAdded(address issuerNFT, address issuerAddress);
    event IssuerRemoved(address issuerNFT);
    event FeeRecipientChanged(address indexed issuerNFT, address newFeeRecipient);

    constructor(address _weth, address _owner) Ownable(_owner) EIP712("SmokeSpendingContract", "1") {
        WETH = IWETH(_weth);
        smokeFeesMaxBps = 500; // 5 BPS maximum total fees
    }

    receive() external payable {
        require(msg.sender == address(WETH), "Direct ETH transfers not allowed");
    }

    modifier onlyIssuer(address issuerNFT) {
        require(issuers[issuerNFT].issuerAddress != address(0), "Invalid issuer");
        require(msg.sender == issuers[issuerNFT].issuerAddress, "Not the issuer");
        _;
    }

    modifier onlySpendingConfig() {
        require(msg.sender == spendingConfigContract, "Not authorised");
        _;
    }

    function setSpendingConfigContract(address _spendingConfigContract) external onlyOwner {
        require(spendingConfigContract == address(0), "Already set");
        spendingConfigContract = _spendingConfigContract;
    }

    function addIssuer(
        address issuerNFT,
        address _issuerAddress,
        uint256 _borrowInterestRate,
        uint256 _autogasThreshold,
        uint256 _autogasRefillAmount,
        uint256 _gasPriceThreshold
    ) external onlyOwner {
        require(issuers[issuerNFT].issuerAddress == address(0), "Issuer already exists");
        
        IssuerData storage newIssuer = issuers[issuerNFT];
        newIssuer.issuerAddress = _issuerAddress;
        newIssuer.borrowInterestRate = _borrowInterestRate;
        newIssuer.autogasThreshold = _autogasThreshold;
        newIssuer.autogasRefillAmount = _autogasRefillAmount;
        newIssuer.gasPriceThreshold = _gasPriceThreshold;

        emit IssuerAdded(issuerNFT, _issuerAddress);
    }

    function removeIssuer(address issuerNFT) external onlyOwner {
        require(issuers[issuerNFT].issuerAddress != address(0), "Issuer does not exist");
        delete issuers[issuerNFT];
        emit IssuerRemoved(issuerNFT);
    }

    function borrow(
        address issuerNFT,
        uint256 nftId,
        uint256 amount,
        uint256 timestamp,
        uint256 signatureValidity,
        uint256 nonce,
        bool weth,
        bytes memory signature
    ) external nonReentrant {
        IssuerData storage issuerData = issuers[issuerNFT];
        require(amount > 0, "Borrow amount must be greater than 0");
        require(block.timestamp <= timestamp + signatureValidity, "Signature expired");
        require(nonce == issuerData.borrowNonces[nftId], "Invalid nonce");
        require(issuerData.issuerAddress != address(0), "Invalid issuer");
        require(issuerData.poolDeposited >= amount, "Insufficient issuer pool");

        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            BORROW_TYPEHASH,
            msg.sender,
            issuerNFT,
            nftId,
            amount,
            timestamp,
            signatureValidity,
            nonce
        )));
        address signer = ECDSA.recover(digest, signature);
        require(signer == issuerData.issuerAddress, "Invalid signature");

        // _executeBorrow(issuerNFT, nftId, msg.sender, amount, weth);
        _executeBorrowAndSend(issuerNFT, nftId, msg.sender, amount, msg.sender, weth);
        issuerData.borrowNonces[nftId]++;
    }

    function borrowWithSignature(
        BorrowParams memory params,
        bytes memory userSignature,
        bytes memory issuerSignature
    ) external nonReentrant {
        uint256 gasStart = gasleft();
        IssuerData storage issuerData = issuers[params.issuerNFT];
        require(params.amount > 0, "Borrow amount must be greater than 0");
        require(block.timestamp <= params.timestamp + params.signatureValidity, "Signature expired");
        require(params.nonce == issuerData.borrowNonces[params.nftId], "Invalid nonce");
        require(issuerData.issuerAddress != address(0), "Invalid issuer");
        require(issuerData.poolDeposited >= params.amount, "Insufficient issuer pool");
        
        // The borrower can be different from the signer. The signer signs with borrower's address in the signature. 
        // The issuer verifies that the signature is from the signer himself. If not he won't approve it. 
        address signer = _validateSignatures(params, userSignature, issuerSignature);

        _executeBorrowAndSend(params.issuerNFT, params.nftId, signer, params.amount, params.recipient, params.weth);
        
        if (params.repayGas) {
            uint256 paymentAmount = (gasStart - gasleft()) * tx.gasprice * 2;
            _executeBorrowAndSend(params.issuerNFT, params.nftId, signer, paymentAmount, msg.sender, params.weth);
        }
        
        issuers[params.issuerNFT].borrowNonces[params.nftId]++;
    }

    function _validateSignatures(
        BorrowParams memory params,
        bytes memory userSignature,
        bytes memory issuerSignature
    ) internal view returns (address) {

        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            BORROW_TYPEHASH,
            params.recipient,
            params.issuerNFT,
            params.nftId,
            params.amount,
            params.timestamp,
            params.signatureValidity,
            params.nonce
        )));
        address signer = ECDSA.recover(digest, userSignature);
        require(ECDSA.recover(digest, issuerSignature) == issuers[params.issuerNFT].issuerAddress, "Invalid signature");

        return signer;
    }

    function _executeBorrowAndSend(address issuerNFT, uint256 nftId, address signer, uint256 amount, address recipient, bool weth) internal {
        IssuerData storage issuerData = issuers[issuerNFT];
        BorrowPosition storage borrowPosition = issuerData.borrowPositions[nftId][signer];
        
        uint256 borrowInterest = calculateCompoundInterest(issuerNFT, borrowPosition.amount, borrowPosition.timestamp, issuerData.borrowInterestRate);
        
        if (!isBorrower(issuerNFT, nftId, signer)) {
            issuerData.borrowers[nftId].push(signer);
        }

        if(weth){
            WETH.transfer(recipient, amount);
        }
        else {
            WETH.withdraw(amount);
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        }

        uint256 totalFees = issuerData.borrowFees + smokeFees;
        uint256 maxAllowedFees = (amount * smokeFeesMaxBps) / 1000000;

        if (totalFees > maxAllowedFees) {
            // Adjust fees proportionally
            uint256 adjustedIssuerFees = (issuerData.borrowFees * maxAllowedFees) / totalFees;
            uint256 adjustedSmokeFees = maxAllowedFees - adjustedIssuerFees;
            
            borrowPosition.amount += borrowInterest + amount + adjustedIssuerFees + adjustedSmokeFees;
            issuerData.smokeFeesCollected += adjustedSmokeFees;
        } else {
            borrowPosition.amount += borrowInterest + amount + issuerData.borrowFees + smokeFees;
            issuerData.smokeFeesCollected += smokeFees;
        }

        borrowPosition.timestamp = block.timestamp;
        issuerData.poolDeposited -= amount;

        emit BorrowedAndSent(issuerNFT, nftId, signer, amount, recipient);
    }

    function isBorrower(address issuerNFT, uint256 nftId, address wallet) internal view returns (bool) {
        address[] storage nftBorrowers = issuers[issuerNFT].borrowers[nftId];
        for (uint i = 0; i < nftBorrowers.length; i++) {
            if (nftBorrowers[i] == wallet) {
                return true;
            }
        }
        return false;
    }

    function triggerAutogas(address issuerNFT, uint256 nftId, address wallet) external onlyIssuer(issuerNFT) {
        IssuerData storage issuerData = issuers[issuerNFT];
        require(wallet.balance < issuerData.autogasThreshold, "Balance above threshold");

        _executeBorrowAndSend(issuerNFT, nftId, wallet, issuerData.autogasRefillAmount, wallet, false);

        emit AutogasTriggered(issuerNFT, nftId, wallet, issuerData.autogasRefillAmount);
    }

    function triggerAutogasSpike(address issuerNFT, uint256 nftId, address wallet) external onlyIssuer(issuerNFT) {
        uint256 gasStart = gasleft();
        IssuerData storage issuerData = issuers[issuerNFT];
        require(wallet.balance < issuerData.autogasThreshold, "Balance above threshold");
        require(issuerData.gasPriceThreshold <= tx.gasprice, "Gas price is below threshold");

        _executeBorrowAndSend(issuerNFT, nftId, wallet, issuerData.autogasRefillAmount, wallet, false);
        uint256 gasUsed = gasStart - gasleft();
        uint256 paymentAmount = gasUsed * tx.gasprice * 2;
        _executeBorrowAndSend(issuerNFT, nftId, wallet, paymentAmount, msg.sender, false);

        emit AutogasSpikeTriggered(issuerNFT, nftId, wallet, issuerData.autogasRefillAmount);
    }

    function repay(address issuerNFT, uint256 nftId, address wallet, address refundAddress) external payable nonReentrant {
        require(msg.value > 0, "Repay amount must be greater than 0");
        
        uint256 repaidAmount = _repayInternal(issuerNFT, nftId, wallet, msg.value);
        
        _handleRefund(msg.value, repaidAmount, refundAddress);
    }

    function repayMultiple(
        address[] calldata issuerNFTs,
        uint256[] calldata nftIds,
        address[] calldata wallets,
        uint256[] calldata amounts,
        address refundAddress
    ) external payable nonReentrant {
        require(issuerNFTs.length == nftIds.length && nftIds.length == wallets.length && wallets.length == amounts.length, "Arrays length mismatch");
        require(msg.value > 0, "Repay amount must be greater than 0");
        
        uint256 totalRepaid = 0;
        
        for (uint i = 0; i < nftIds.length; i++) {
            totalRepaid += _repayInternal(issuerNFTs[i], nftIds[i], wallets[i], amounts[i]);
        }
    
        require(totalRepaid <= msg.value, "Insufficient ETH sent");
        _handleRefund(msg.value, totalRepaid, refundAddress);
    }

    function _repayInternal(address issuerNFT, uint256 nftId, address wallet, uint256 amount) internal returns (uint256) {
        IssuerData storage issuerData = issuers[issuerNFT];
        require(address(issuerData.issuerAddress) != address(0), "Invalid issuer");

        BorrowPosition storage borrowPosition = issuerData.borrowPositions[nftId][wallet];
        require(borrowPosition.amount > 0, "No borrow position for this NFT and wallet");

        uint256 borrowInterest = calculateCompoundInterest(issuerNFT, borrowPosition.amount, borrowPosition.timestamp, issuerData.borrowInterestRate);
        uint256 totalOwed = borrowPosition.amount + borrowInterest;
        
        uint256 repayAmount = amount > totalOwed ? totalOwed : amount;
        borrowPosition.amount = totalOwed > repayAmount ? totalOwed - repayAmount : 0;
        borrowPosition.timestamp = block.timestamp;

        issuerData.poolDeposited += repayAmount;
        emit Repaid(issuerNFT, nftId, wallet, repayAmount);

        return repayAmount;
    }

    function _handleRefund(uint256 totalSent, uint256 totalRepaid, address refundAddress) internal {
        WETH.deposit{value: totalRepaid}();
        
        if (totalRepaid < totalSent) {
            uint256 refundAmount = totalSent - totalRepaid;
            (bool success, ) = refundAddress.call{value: refundAmount}("");
            require(success, "ETH refund failed");
        }
    }

    function calculateCompoundInterest(address issuerNFT, uint256 principal, uint256 lastUpdateTime, uint256 currentInterestRate) internal view returns (uint256) {
        if (principal == 0) return 0;
    
        uint256 totalInterest = 0;
        uint256 currentPrincipal = principal;
        uint256 currentTime = lastUpdateTime;
        InterestRateChange[] storage rateHistory = issuers[issuerNFT].interestRateHistory[currentInterestRate];
    
        for (uint i = 0; i < rateHistory.length && rateHistory[i].timestamp <= block.timestamp; i++) {
            if (rateHistory[i].timestamp > lastUpdateTime) {
                uint256 periodInterest = calculatePeriodInterest(currentPrincipal, currentTime, rateHistory[i].timestamp, currentInterestRate);
                totalInterest += periodInterest;
                currentPrincipal += periodInterest;
                currentTime = rateHistory[i].timestamp;
                currentInterestRate = rateHistory[i].rate;
            }
        }
    
        totalInterest += calculatePeriodInterest(currentPrincipal, currentTime, block.timestamp, currentInterestRate);
    
        return totalInterest;
    }
    
    function calculatePeriodInterest(uint256 principal, uint256 startTime, uint256 endTime, uint256 interestRate) internal pure returns (uint256) {
        uint256 timeElapsed = endTime - startTime;
        uint256 ratePerSecond = interestRate * 1e18 / (SECONDS_PER_YEAR * 10000); // Convert basis points to per-second rate
        uint256 compoundFactor = compoundExponent(ratePerSecond, timeElapsed);
        uint256 compoundedAmount = (principal * compoundFactor) / 1e18;
        return compoundedAmount - principal;
    }

    function compoundExponent(uint256 rate, uint256 time) internal pure returns (uint256) {
        uint256 result = 1e18;
        uint256 base = 1e18 + rate;
        while (time > 0) {
            if (time % 2 == 1) {    
                result = (result * base) / 1e18;
            }
            base = (base * base) / 1e18;
            time /= 2;
        }
        return result;
    }

    function poolDeposit(address issuerNFT) external payable onlyIssuer(issuerNFT) {
        WETH.deposit{value: msg.value}();
        issuers[issuerNFT].poolDeposited += msg.value;
        emit PoolDeposited(issuerNFT, msg.value);
    }

    function poolWithdraw(uint256 amount, address issuerNFT) external onlyIssuer(issuerNFT) {
        IssuerData storage issuerData = issuers[issuerNFT];

        require(issuerData.poolDeposited - issuerData.smokeFeesCollected >= amount, "Insufficient pool balance");
        WETH.withdraw(amount);
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
        issuers[issuerNFT].poolDeposited -= amount;
        emit PoolWithdrawn(issuerNFT, amount);
    }

    function setInterestRate(address issuerNFT, uint256 newRate) external onlySpendingConfig {
        IssuerData storage issuerData = issuers[issuerNFT];
        issuerData.borrowInterestRate = newRate;
        issuerData.interestRateHistory[issuerData.borrowInterestRate].push(InterestRateChange(block.timestamp, issuerData.borrowInterestRate));
        emit InterestRateChanged(issuerNFT, newRate);
    }

    function setAutogasThreshold(address issuerNFT, uint256 newThreshold) external onlySpendingConfig {
        issuers[issuerNFT].autogasThreshold = newThreshold;
    }

    function setGaspriceThreshold(address issuerNFT, uint256 newThreshold) external onlySpendingConfig {
        issuers[issuerNFT].gasPriceThreshold = newThreshold;
        emit GasPriceThresholdChanged(issuerNFT, newThreshold);
    }

    function setAutogasRefillAmount(address issuerNFT, uint256 newAmount) external onlySpendingConfig {
        issuers[issuerNFT].autogasRefillAmount = newAmount;
    }

    function setSmokeFees(uint256 _newFees) external onlySpendingConfig {
        // require(smokeFees<42e12, 'fees too high');
        smokeFees = _newFees;
    }

    function setSmokeFeesMaxBps(uint256 _newFeesMaxBps) external onlySpendingConfig {
        smokeFeesMaxBps = _newFeesMaxBps;
    }

    function setBorrowFees(address issuerNFT, uint256 newFees) external onlySpendingConfig {
        // require(newFees<1e14, 'fees too high');
        issuers[issuerNFT].borrowFees = newFees;
    }

    function getBorrowPosition(address issuerNFT, uint256 nftId, address wallet) external view returns (uint256 borrowAmount) {
        IssuerData storage issuerData = issuers[issuerNFT];
        BorrowPosition memory borrowPosition = issuerData.borrowPositions[nftId][wallet];
        borrowAmount = borrowPosition.amount + calculateCompoundInterest(issuerNFT, borrowPosition.amount, borrowPosition.timestamp, issuerData.borrowInterestRate);
    }

    function getBorrowPositionSeparate(address issuerNFT, uint256 nftId, address wallet) external view returns (uint256 borrowAmount, uint256 interestAmount, uint256 borrowTimestamp) {
        IssuerData storage issuerData = issuers[issuerNFT];
        BorrowPosition memory borrowPosition = issuerData.borrowPositions[nftId][wallet];
        borrowAmount = borrowPosition.amount;
        borrowTimestamp = borrowPosition.timestamp;
        interestAmount = calculateCompoundInterest(issuerNFT, borrowPosition.amount, borrowPosition.timestamp, issuerData.borrowInterestRate);
    }

    function getBorrowFees(address issuerNFT) external view returns(uint256) {
        return issuers[issuerNFT].borrowFees;
    }

    function getCurrentNonce(address issuerNFT, uint256 nftId) external view returns (uint256) {
        return issuers[issuerNFT].borrowNonces[nftId];
    }

    function getIssuerAddress(address issuerNFT) external view returns (address) {
        return issuers[issuerNFT].issuerAddress;
    }

    function getPoolDeposited(address issuerNFT) external view returns (uint256) {
        return issuers[issuerNFT].poolDeposited;
    }

    function getBorrowInterestRate(address issuerNFT) external view returns (uint256) {
        return issuers[issuerNFT].borrowInterestRate;
    }

    function getAutogasThreshold(address issuerNFT) external view returns (uint256) {
        return issuers[issuerNFT].autogasThreshold;
    }

    function getAutogasRefillAmount(address issuerNFT) external view returns (uint256) {
        return issuers[issuerNFT].autogasRefillAmount;
    }

    function getGasPriceThreshold(address issuerNFT) external view returns (uint256) {
        return issuers[issuerNFT].gasPriceThreshold;
    }
}