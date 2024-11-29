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

    struct RepayPosition {
        uint256 amount;
        uint256 timestamp;
    }

    struct TotalBorrowPosition {
        uint256 amount;
        uint256 timestamp;
    }

    address public immutable issuer;
    IWETH public immutable WETH;

    mapping(uint256 => mapping(address => BorrowPosition)) public borrowPositions; // nftId => wallet => BorrowPosition
    mapping(uint256 => RepayPosition) public repayPositions; // nftId => RepayPosition
    mapping(uint256 => uint256) public borrowNonces; // nftId => chainId => nonce
    mapping(uint256 => TotalBorrowPosition) public totalBorrowPositions; // nftId => TotalBorrowPosition

    uint256 public borrowInterestRate; // Annual interest rate in basis points (1% = 100)
    uint256 public constant SECONDS_PER_YEAR = 31536000;
    uint256 public autogasThreshold;
    uint256 public autogasRefillAmount; // Fixed amount for autogas refill
    uint256 public repaymentThreshold; // Threshold for considering a debt fully repaid
    uint256 public constant SIGNATURE_VALIDITY = 5 minutes;
    uint256 public immutable chainId;

    event Borrowed(uint256 indexed nftId, address indexed wallet, uint256 amount);
    event BorrowedAndSent(uint256 indexed nftId, address indexed wallet, address recipient, uint256 amount);
    event AutogasTriggered(uint256 indexed nftId, address indexed wallet, uint256 amount);
    event Repaid(uint256 indexed nftId, uint256 amount);
    event Lent(uint256 indexed nftId, uint256 amount);
    event PoolDeposited(uint256 amount);
    event PoolWithdrawn(uint256 amount);

    constructor(address _issuer, address _weth) Ownable(msg.sender) {
        issuer = _issuer;
        WETH = IWETH(_weth);
        borrowInterestRate = 1000; // 10% annual interest
        autogasThreshold = 1e18; // 1 ETH
        autogasRefillAmount = 5e17; // 0.5 ETH, adjust as needed
        repaymentThreshold = 1e13; // 0.00000001 ETH
        chainId = block.chainid;
    }

    receive() external payable {
        require(msg.sender == address(WETH), "Direct ETH transfers not allowed");
    }

    modifier onlyIssuer() {
        require(msg.sender == issuer, "Not the issuer");
        _;
    }

    function borrow(uint256 nftId, uint256 amount, uint256 timestamp, uint256 nonce, bytes memory signature)
        external
        nonReentrant
    {
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
        bytes memory userSignature,
        bytes memory issuerSignature
    ) external nonReentrant {
        require(amount > 0, "Borrow amount must be greater than 0");
        require(block.timestamp <= timestamp + SIGNATURE_VALIDITY, "Signature expired");
        require(nonce == borrowNonces[nftId], "Invalid nonce");

        bytes32 messageHash = keccak256(abi.encodePacked(nftId, amount, timestamp, nonce, chainId));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

        address signer = ethSignedMessageHash.recover(userSignature);
        require(ethSignedMessageHash.recover(issuerSignature) == issuer, "Invalid signature");

        _executeBorrow(nftId, signer, amount);
        borrowNonces[nftId]++;
    }

    function _executeBorrow(uint256 nftId, address wallet, uint256 amount) internal {
        BorrowPosition storage borrowPosition = borrowPositions[nftId][msg.sender];
        TotalBorrowPosition storage totalBorrowPosition = totalBorrowPositions[nftId];

        uint256 borrowInterest =
            calculateCompoundInterest(borrowPosition.amount, borrowPosition.timestamp, borrowInterestRate);
        uint256 totalBorrowInterest =
            calculateCompoundInterest(totalBorrowPosition.amount, totalBorrowPosition.timestamp, borrowInterestRate);

        borrowPosition.amount += borrowInterest + amount;
        borrowPosition.timestamp = block.timestamp;

        totalBorrowPosition.amount += totalBorrowInterest + amount;
        totalBorrowPosition.timestamp = block.timestamp;

        WETH.withdraw(amount);
        (bool success,) = wallet.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit Borrowed(nftId, wallet, amount);
    }

    function triggerAutogas(uint256 nftId, address wallet) external onlyIssuer {
        require(wallet.balance < autogasThreshold, "Balance above threshold");

        _executeBorrow(nftId, wallet, autogasRefillAmount);

        emit AutogasTriggered(nftId, wallet, autogasRefillAmount);
    }

    function repay(uint256 nftId) external payable nonReentrant {
        require(msg.value > 0, "Repay amount must be greater than 0");

        TotalBorrowPosition storage totalBorrowPosition = totalBorrowPositions[nftId];
        RepayPosition storage repayPosition = repayPositions[nftId];

        uint256 totalBorrowInterest =
            calculateCompoundInterest(totalBorrowPosition.amount, totalBorrowPosition.timestamp, borrowInterestRate);
        uint256 repayInterest =
            calculateCompoundInterest(repayPosition.amount, repayPosition.timestamp, borrowInterestRate);

        uint256 totalBorrowed = totalBorrowPosition.amount + totalBorrowInterest;
        uint256 currentRepayAmount = repayPosition.amount + repayInterest;

        uint256 maxRepayable = totalBorrowed > currentRepayAmount ? totalBorrowed - currentRepayAmount : 0;
        uint256 actualRepayAmount = msg.value > maxRepayable ? maxRepayable : msg.value;

        if (actualRepayAmount > 0) {
            repayPosition.amount += actualRepayAmount + repayInterest;
            repayPosition.timestamp = block.timestamp;

            WETH.deposit{value: actualRepayAmount}();

            emit Repaid(nftId, actualRepayAmount);
        }

        if (actualRepayAmount < msg.value) {
            uint256 refundAmount = msg.value - actualRepayAmount;
            (bool success,) = msg.sender.call{value: refundAmount}("");
            require(success, "ETH refund failed");
        }
    }

    function calculateCompoundInterest(uint256 principal, uint256 lastUpdateTime, uint256 interestRate)
        internal
        view
        returns (uint256)
    {
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
        RepayPosition memory repayPosition = repayPositions[nftId];

        uint256 borrowAmount = borrowPosition.amount
            + calculateCompoundInterest(borrowPosition.amount, borrowPosition.timestamp, borrowInterestRate);
        uint256 repayAmount = repayPosition.amount
            + calculateCompoundInterest(repayPosition.amount, repayPosition.timestamp, borrowInterestRate);

        int256 netPosition = int256(repayAmount) - int256(borrowAmount);

        if (netPosition > -int256(repaymentThreshold) && netPosition < int256(repaymentThreshold)) {
            return 0; // Consider the debt fully repaid if within the threshold
        }

        return netPosition;
    }

    function getBorrowPosition(uint256 nftId, address wallet) external view returns (uint256) {
        BorrowPosition memory borrowPosition = borrowPositions[nftId][wallet];
        uint256 borrowAmount = borrowPosition.amount
            + calculateCompoundInterest(borrowPosition.amount, borrowPosition.timestamp, borrowInterestRate);
        return borrowAmount;
    }

    function getRepayPosition(uint256 nftId) external view returns (uint256) {
        RepayPosition memory repayPosition = repayPositions[nftId];
        uint256 repayAmount = repayPosition.amount
            + calculateCompoundInterest(repayPosition.amount, repayPosition.timestamp, borrowInterestRate);
        return repayAmount;
    }

    function getTotalBorrowPosition(uint256 nftId) external view returns (uint256) {
        TotalBorrowPosition memory totalBorrowPosition = totalBorrowPositions[nftId];
        uint256 totalBorrowAmount = totalBorrowPosition.amount
            + calculateCompoundInterest(totalBorrowPosition.amount, totalBorrowPosition.timestamp, borrowInterestRate);
        return totalBorrowAmount;
    }

    function poolDeposit(uint256 amount) external payable onlyIssuer {
        require(msg.value == amount, "Incorrect ETH amount sent");
        WETH.deposit{value: amount}();
        emit PoolDeposited(amount);
    }

    function poolWithdraw(uint256 amount) external onlyIssuer {
        WETH.withdraw(amount);
        (bool success,) = issuer.call{value: amount}("");
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
