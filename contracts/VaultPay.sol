// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title VaultPay
/// @notice Escrow-style ERC20 payment contract.
/// @dev Implement the TODO sections below.
contract VaultPay is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum PaymentStatus {
        None,
        Created,
        Claimed,
        Cancelled
    }

    struct Payment {
        address payer;
        address recipient;
        uint256 amount;
        uint64 createdAt;
        uint64 deadline;
        PaymentStatus status;
        bytes32 memoHash;
    }

    IERC20 public immutable token;
    uint256 public nextPaymentId = 1;

    mapping(uint256 paymentId => Payment payment) private payments;

    event PaymentCreated(
        uint256 indexed paymentId,
        address indexed payer,
        address indexed recipient,
        uint256 amount,
        uint64 deadline,
        bytes32 memoHash
    );
    event PaymentClaimed(uint256 indexed paymentId, address indexed recipient, uint256 amount);
    event PaymentCancelled(uint256 indexed paymentId, address indexed payer, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error InvalidDeadline();
    error PaymentNotFound();
    error PaymentNotActive();
    error NotRecipient();
    error NotPayer();
    error PaymentExpired();
    error PaymentNotExpired();

    constructor(IERC20 token_) {
        if (address(token_) == address(0)) revert ZeroAddress();
        token = token_;
    }

    /// @notice Create an escrowed ERC20 payment for `recipient`.
    /// @param recipient Wallet allowed to claim the payment.
    /// @param amount Token amount in base units.
    /// @param deadline Unix timestamp after which payer may cancel and reclaim tokens.
    /// @param memoHash Optional keccak256 hash of a memo string for off-chain reference.
    function createPayment(
        address recipient,
        uint256 amount,
        uint64 deadline,
        bytes32 memoHash
    ) external nonReentrant returns (uint256 paymentId) {
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (deadline < block.timestamp) {
            revert InvalidDeadline();
        }

        uint256 id = nextPaymentId++;

        payments[id] = Payment({
            payer: msg.sender,
            recipient: recipient,
            amount: amount,
            createdAt: uint64(block.timestamp),
            deadline: deadline,
            status: PaymentStatus.Created,
            memoHash: memoHash
        });

        token.transferFrom(msg.sender, address(this), amount);
        
        emit PaymentCreated(id, msg.sender, recipient, amount, deadline, memoHash);
        return id;
    }

    /// @notice Claim an active payment.
    /// @dev Only the intended recipient should be able to claim.
    function claimPayment(uint256 paymentId) external nonReentrant {
        Payment memory payment = payments[paymentId];
        if (payment.status == PaymentStatus.None) {
            revert PaymentNotFound();
        }
        if (payment.status == PaymentStatus.Claimed) {
            revert PaymentNotActive();
        }
        if (payment.recipient != msg.sender) {
            revert NotRecipient();
        }
        if (payment.deadline < block.timestamp) {
            revert PaymentExpired();
        }

        token.transfer(payment.recipient, payment.amount);
        payments[paymentId].status = PaymentStatus.Claimed;
        emit PaymentClaimed(paymentId, payment.recipient, payment.amount);
    }

    /// @notice Cancel an expired active payment and refund payer.
    /// @dev Only the original payer should be able to cancel after deadline.
    function cancelPayment(uint256 paymentId) external nonReentrant {
        Payment memory payment = payments[paymentId];
        if (payment.status == PaymentStatus.None) {
            revert PaymentNotFound();
        }
        if (payment.payer != msg.sender) {
            revert NotPayer();
        }
        if (payment.status == PaymentStatus.Claimed) {
            revert PaymentNotActive();
        }
        if (payment.deadline > block.timestamp) {
            revert PaymentNotExpired();
        }

        token.transfer(payment.payer, payment.amount);
        payments[paymentId].status = PaymentStatus.Cancelled;
        emit PaymentCancelled(paymentId, payment.payer, payment.amount);
    }

    function getPayment(uint256 paymentId) external view returns (Payment memory) {
        return payments[paymentId];
    }
}
