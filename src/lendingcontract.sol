// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
}

contract CrossChainLendingContract is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    struct BorrowPosition {
        uint256 amount;
        uint256 timestamp;
    }

    address public immutable issuer;
    IWETH public immutable WETH;
    
    mapping(uint256 => mapping(address => BorrowPosition)) public borrowPositions; // nftId => wallet => BorrowPosition
    mapping(uint256 => uint256) public borrowNonces; // nftId => chainId => nonce
    mapping(uint256 => address[]) public borrowers; // nftId => array of borrower addresses

    uint256 public borrowInterestRate; // Annual interest rate in basis points (1% = 100)
    uint256 public constant SECONDS_PER_YEAR = 31536000;
    uint256 public autogasThreshold;
    uint256 public autogasRefillAmount; // Fixed amount for autogas refill
    uint256 public repaymentThreshold; // Threshold for considering a debt fully repaid
    uint256 public gasPriceThreshold; // Threshold for considering a debt fully repaid
    uint256 public constant SIGNATURE_VALIDITY = 5 minutes;
    uint256 public immutable chainId;

    event Borrowed(uint256 indexed nftId, address indexed wallet, uint256 amount);
    event BorrowedAndSent(uint256 indexed nftId, address indexed wallet, uint256 amount, address recipient);
    event AutogasTriggered(uint256 indexed nftId, address indexed wallet, uint256 amount);
    event AutogasSpikeTriggered(uint256 indexed nftId, address indexed wallet, uint256 amount);
    event Repaid(uint256 indexed nftId, address indexed wallet, uint256 amount);
    event PoolDeposited(uint256 amount);
    event PoolWithdrawn(uint256 amount);

    constructor(address _issuer, address _weth, uint256 _chainId) Ownable(msg.sender) {
        issuer = _issuer;
        WETH = IWETH(_weth);
        borrowInterestRate = 1000; // 10% annual interest
        autogasThreshold = 1e15; // 0.001 ETH
        autogasRefillAmount = 5e14  ; // 0.0005 ETH, adjust as needed
        repaymentThreshold = 1e13; // 0.00001 ETH aka $0.035 at current prices
        gasPriceThreshold = 2; 
        chainId = _chainId;
    }

    receive() external payable {
        require(msg.sender == address(WETH), "Direct ETH transfers not allowed");
    }

    modifier onlyIssuer() {
        require(msg.sender == issuer, "Not the issuer");
        _;
    }

    function borrow(
        uint256 nftId,
        uint256 amount,
        uint256 timestamp,
        uint256 nonce,
        bytes memory signature
    ) external nonReentrant {
        require(amount > 0, "Borrow amount must be greater than 0");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(nonce == borrowNonces[nftId], "Invalid nonce");

        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, nftId, amount, timestamp, nonce, chainId));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        require(ethSignedMessageHash.recover(signature) == issuer, "Invalid signature");

        _executeBorrow(nftId, msg.sender, amount);
        borrowNonces[nftId]++;
    }

    function borrowWithSignature(
        uint256 nftId,
        uint256 amount,
        uint256 timestamp,
        uint256 nonce,
        address recipient,
        bytes memory userSignature,
        bytes memory issuerSignature
    ) external nonReentrant {
        require(amount > 0, "Borrow amount must be greater than 0");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(nonce == borrowNonces[nftId], "Invalid nonce");
        
        // The borrower can be different from the signer. The signer signs with borrower's address in the signature. 
        // The issuer verifies that the signature is from the signer himself. If not he won't approve it. 
        bytes32 messageHash = keccak256(abi.encodePacked(recipient, nftId, amount, timestamp, nonce, chainId));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        
        address signer = ethSignedMessageHash.recover(userSignature);
        require(ethSignedMessageHash.recover(issuerSignature) == issuer, "Invalid signature");

        uint256 gasStart = gasleft();
        _executeBorrowAndSend(nftId, signer, amount, recipient);
        uint256 gasUsed = gasStart - gasleft();
        uint256 paymentAmount = gasUsed * tx.gasprice * 2;
        _executeBorrowAndSend(nftId, signer, paymentAmount, msg.sender);
        borrowNonces[nftId]++;
    }

    function _executeBorrow(uint256 nftId, address wallet, uint256 amount) internal {
        BorrowPosition storage borrowPosition = borrowPositions[nftId][wallet];
        
        uint256 borrowInterest = calculateCompoundInterest(borrowPosition.amount, borrowPosition.timestamp, borrowInterestRate);
        
        if (!isBorrower(nftId, wallet)) {
            borrowers[nftId].push(wallet);
        }

        borrowPosition.amount += borrowInterest + amount;
        borrowPosition.timestamp = block.timestamp;

        WETH.withdraw(amount);
        (bool success, ) = wallet.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit Borrowed(nftId, wallet, amount);
    }

    function _executeBorrowAndSend(uint256 nftId, address wallet, uint256 amount, address recipient) internal {
        BorrowPosition storage borrowPosition = borrowPositions[nftId][wallet];
        
        uint256 borrowInterest = calculateCompoundInterest(borrowPosition.amount, borrowPosition.timestamp, borrowInterestRate);
        
        if (!isBorrower(nftId, wallet)) {
            borrowers[nftId].push(wallet);
        }

        borrowPosition.amount += borrowInterest + amount;
        borrowPosition.timestamp = block.timestamp;

        WETH.withdraw(amount);
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit BorrowedAndSent(nftId, wallet, amount, recipient);
    }

    function isBorrower(uint256 nftId, address wallet) internal view returns (bool) {
        address[] storage nftBorrowers = borrowers[nftId];
        for (uint i = 0; i < nftBorrowers.length; i++) {
            if (nftBorrowers[i] == wallet) {
                return true;
            }
        }
        return false;
    }

    function triggerAutogas(uint256 nftId, address wallet) external onlyIssuer {
        require(wallet.balance < autogasThreshold, "Balance above threshold");

        _executeBorrow(nftId, wallet, autogasRefillAmount);

        emit AutogasTriggered(nftId, wallet, autogasRefillAmount);
    }

    function triggerAutogasSpike(uint256 nftId, address wallet) external onlyIssuer {
        require(wallet.balance < autogasThreshold, "Balance above threshold");
        require(gasPriceThreshold <= tx.gasprice, "Gas price is below threshold");

        uint256 gasStart = gasleft();
        _executeBorrow(nftId, wallet, autogasRefillAmount);
        uint256 gasUsed = gasStart - gasleft();
        uint256 paymentAmount = gasUsed * tx.gasprice * 2;
        _executeBorrowAndSend(nftId, wallet, paymentAmount, issuer);

        emit AutogasSpikeTriggered(nftId, wallet, autogasRefillAmount);
    }

    function repay(uint256 nftId, address wallet, address refundAddress) external payable nonReentrant {
        require(msg.value > 0, "Repay amount must be greater than 0");
        
        BorrowPosition storage borrowPosition = borrowPositions[nftId][wallet];
        require(borrowPosition.amount > 0, "No borrow position for this NFT and wallet");

        uint256 borrowInterest = calculateCompoundInterest(borrowPosition.amount, borrowPosition.timestamp, borrowInterestRate);
        uint256 totalOwed = borrowPosition.amount + borrowInterest;
        
        uint256 repayAmount = msg.value > totalOwed ? totalOwed : msg.value;
        borrowPosition.amount = totalOwed > repayAmount ? totalOwed - repayAmount : 0;
        borrowPosition.timestamp = block.timestamp;

        WETH.deposit{value: repayAmount}();
        
        if (repayAmount < msg.value) {
            uint256 refundAmount = msg.value - repayAmount;
            (bool success, ) = refundAddress.call{value: refundAmount}("");
            require(success, "ETH refund failed");
        }

        emit Repaid(nftId, wallet, repayAmount);
    }

    function repayMultiple(uint256[] memory nftIds, address[] memory wallets, uint256[] memory amounts, address refundAddress) external payable nonReentrant {
        require(nftIds.length == wallets.length && wallets.length == amounts.length, "Arrays length mismatch");
        require(msg.value > 0, "Repay amount must be greater than 0");
        
        uint256 totalRepaid = 0;
        
        for (uint i = 0; i < nftIds.length; i++) {
            BorrowPosition storage borrowPosition = borrowPositions[nftIds[i]][wallets[i]];
            require(borrowPosition.amount > 0, "No borrow position for this NFT and wallet");
    
            uint256 borrowInterest = calculateCompoundInterest(borrowPosition.amount, borrowPosition.timestamp, borrowInterestRate);
            uint256 totalOwed = borrowPosition.amount + borrowInterest;
            
            uint256 repayAmount = amounts[i] > totalOwed ? totalOwed : amounts[i];
            borrowPosition.amount = totalOwed - repayAmount;
            borrowPosition.timestamp = block.timestamp;
    
            totalRepaid += repayAmount;
            emit Repaid(nftIds[i], wallets[i], repayAmount);
        }
    
        require(totalRepaid <= msg.value, "Insufficient ETH sent");
        WETH.deposit{value: totalRepaid}();
        
        if (totalRepaid < msg.value) {
            (bool success, ) = refundAddress.call{value: msg.value - totalRepaid}("");
            require(success, "ETH refund failed");
        }
    }

    function calculateCompoundInterest(uint256 principal, uint256 lastUpdateTime, uint256 interestRate) internal view returns (uint256) {
        if (principal == 0) return 0;
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
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

    function getNetPosition(uint256 nftId, address wallet) external view returns (int256) {
        BorrowPosition memory borrowPosition = borrowPositions[nftId][wallet];
        uint256 borrowAmount = borrowPosition.amount + calculateCompoundInterest(borrowPosition.amount, borrowPosition.timestamp, borrowInterestRate);
        
        if (borrowAmount < repaymentThreshold) {
            return 0; // Consider the debt fully repaid if within the threshold
        }
        return -int256(borrowAmount);
    }

    function getBorrowPosition(uint256 nftId, address wallet) external view returns (uint256) {
        BorrowPosition memory borrowPosition = borrowPositions[nftId][wallet];
        uint256 borrowAmount = borrowPosition.amount + calculateCompoundInterest(borrowPosition.amount, borrowPosition.timestamp, borrowInterestRate);
        return borrowAmount;
    }

    function poolDeposit(uint256 amount) external payable onlyIssuer {
        require(msg.value == amount, "Incorrect ETH amount sent");
        WETH.deposit{value: amount}();
        emit PoolDeposited(amount);
    }

    function poolWithdraw(uint256 amount) external onlyIssuer {
        WETH.withdraw(amount);
        (bool success, ) = issuer.call{value: amount}("");
        require(success, "ETH transfer failed");
        emit PoolWithdrawn(amount);
    }

    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function setBorrowInterestRate(uint256 newRate) external onlyOwner {
        borrowInterestRate = newRate;
    }

    function setAutogasThreshold(uint256 newThreshold) external onlyOwner {
        autogasThreshold = newThreshold;
    }

    function setAutogasRefillAmount(uint256 newAmount) external onlyOwner {
        autogasRefillAmount = newAmount;
    }

    function setRepaymentThreshold(uint256 newThreshold) external onlyOwner {
        repaymentThreshold = newThreshold;
    }

    function getCurrentNonce(uint256 nftId) external view returns (uint256) {
        return borrowNonces[nftId];
    }
}