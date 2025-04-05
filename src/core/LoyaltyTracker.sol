// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IFORT} from "../interfaces/IFORT.sol";

/**
 * @title Loyalty Tracker
 * @notice Manages player loyalty rewards and lossless refunds
 * @dev Features:
 * - Consecutive loss tracking with FORT refunds
 * - Tier-based ticket discounts
 * - DAO-configurable parameters
 */
contract LoyaltyTracker is AccessControl, ReentrancyGuard {
    // -----------------------------
    // Constants & Roles
    // -----------------------------
    bytes32 public constant TRACKER_ROLE = keccak256("TRACKER_ROLE");
    uint256 public constant BASIS_POINTS = 10000;

    // -----------------------------
    // Structures
    // -----------------------------
    struct TierConfig {
        uint256 requiredTickets;
        uint256 discountBPS; // Discount in basis points
    }

    // -----------------------------
    // State Variables
    // -----------------------------
    IFORT public immutable fortToken;

    // Lossless parameters
    uint256 public refundThreshold = 10;
    uint256 public refundAmount = 50 ether; // 50 FORT

    // Tier system
    TierConfig[] public tiers;
    mapping(address => uint256) public totalTickets;
    mapping(address => uint256) public lossStreak;

    // -----------------------------
    // Events
    // -----------------------------
    event RefundClaimed(address indexed user, uint256 amount);
    event TierAdded(uint256 requiredTickets, uint256 discountBPS);
    event TierUpdated(uint256 index, uint256 discountBPS);
    event RefundConfigUpdated(uint256 threshold, uint256 amount);

    // -----------------------------
    // Errors
    // -----------------------------
    error UnauthorizedAccess();
    error InsufficientLosses();
    error InvalidTierConfig();
    error TierIndexOutOfBounds();

    // -----------------------------
    // Constructor
    // -----------------------------
    constructor(address _fortToken, address _daoAdmin) {
        fortToken = IFORT(_fortToken);
        _grantRole(DEFAULT_ADMIN_ROLE, _daoAdmin);
        _grantRole(TRACKER_ROLE, msg.sender);

        // Initialize default tiers
        tiers.push(TierConfig(100, 500)); // Tier 1: 100 tickets → 5% discount
        tiers.push(TierConfig(500, 1000)); // Tier 2: 500 tickets → 10% discount
        tiers.push(TierConfig(1000, 1500)); // Tier 3: 1000 tickets → 15% discount
    }

    // -----------------------------
    // Core Logic
    // -----------------------------

    /**
     * @notice Record player participation and losses
     * @param user Address to update
     * @param ticketsBought Number of tickets purchased
     * @param hasWon Whether user won in this round
     * @dev Callable only by LotteryManager
     */
    function recordParticipation(
        address user,
        uint256 ticketsBought,
        bool hasWon
    ) external onlyRole(TRACKER_ROLE) {
        totalTickets[user] += ticketsBought;

        if (hasWon) {
            lossStreak[user] = 0;
        } else {
            lossStreak[user] += ticketsBought;
        }
    }

    /**
     * @notice Claim FORT refund for consecutive losses
     * @dev Resets loss streak upon claim
     */
    function claimRefund() external nonReentrant {
        uint256 currentStreak = lossStreak[msg.sender];
        if (currentStreak < refundThreshold) revert InsufficientLosses();

        uint256 refundsEarned = (currentStreak / refundThreshold) *
            refundAmount;
        lossStreak[msg.sender] = currentStreak % refundThreshold;

        fortToken.mint(msg.sender, refundsEarned);
        emit RefundClaimed(msg.sender, refundsEarned);
    }

    // -----------------------------
    // Tier System
    // -----------------------------

    /**
     * @notice Get current discount for a user
     * @param user Address to check
     * @return discountBPS Discount in basis points
     */
    function getDiscount(
        address user
    ) public view returns (uint256 discountBPS) {
        uint256 userTickets = totalTickets[user];
        for (uint256 i = tiers.length; i > 0; i--) {
            if (userTickets >= tiers[i - 1].requiredTickets) {
                return tiers[i - 1].discountBPS;
            }
        }
        return 0;
    }

    // -----------------------------
    // Admin Functions
    // -----------------------------

    /**
     * @notice Add new loyalty tier
     * @param requiredTickets Tickets needed to reach tier
     * @param discountBPS Discount in basis points
     */
    function addTier(
        uint256 requiredTickets,
        uint256 discountBPS
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (discountBPS > BASIS_POINTS) revert InvalidTierConfig();
        tiers.push(TierConfig(requiredTickets, discountBPS));
        emit TierAdded(requiredTickets, discountBPS);
    }

    /**
     * @notice Update existing tier discount
     * @param index Tier index to modify
     * @param newDiscountBPS New discount in basis points
     */
    function updateTier(
        uint256 index,
        uint256 newDiscountBPS
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (index >= tiers.length) revert TierIndexOutOfBounds();
        if (newDiscountBPS > BASIS_POINTS) revert InvalidTierConfig();
        tiers[index].discountBPS = newDiscountBPS;
        emit TierUpdated(index, newDiscountBPS);
    }

    /**
     * @notice Configure lossless refund parameters
     * @param newThreshold New consecutive loss threshold
     * @param newAmount New FORT refund amount per threshold
     */
    function setRefundConfig(
        uint256 newThreshold,
        uint256 newAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        refundThreshold = newThreshold;
        refundAmount = newAmount;
        emit RefundConfigUpdated(newThreshold, newAmount);
    }
}
