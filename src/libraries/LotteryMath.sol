// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Structs} from "./Structs.sol";

/**
 * @title Lottery Mathematics Library
 * @notice Secure mathematical operations for lottery mechanics
 * @dev All functions are internal and pure for gas efficiency
 */
library LotteryMath {
    using SafeCast for uint256;

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MAX_WINNERS = 10;

    error InvalidPercentage();
    error ZeroTotalAmount();
    error InvalidRandomSeed();
    error EmptyTierList();

    // -----------------------------
    // Prize Distribution
    // -----------------------------

    /**
     * @notice Calculate prize distribution from total pool
     * @param totalAmount Total prize pool amount
     * @return dist Structured prize distribution
     */
    function calculatePrizeDistribution(
        uint256 totalAmount
    ) internal pure returns (Structs.PrizeDistribution memory dist) {
        if (totalAmount == 0) revert ZeroTotalAmount();

        dist.grandPrize = (totalAmount * 7000) / BASIS_POINTS; // 70%
        dist.secondaryPrizes = (totalAmount * 2000) / BASIS_POINTS; // 20%
        dist.daoShare = totalAmount - dist.grandPrize - dist.secondaryPrizes; // 10%
    }

    // -----------------------------
    // Randomness Expansion
    // -----------------------------

    /**
     * @notice Generate multiple random numbers from a single seed
     * @param seed Initial random value
     * @param count Number of values to generate
     * @return expanded Array of random numbers
     */
    function expandRandomness(
        uint256 seed,
        uint256 count
    ) internal pure returns (uint256[] memory expanded) {
        if (count == 0 || count > MAX_WINNERS) revert InvalidRandomSeed();

        expanded = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            expanded[i] = uint256(keccak256(abi.encode(seed, i)));
        }
    }

    // -----------------------------
    // Loyalty Discounts
    // -----------------------------

    /**
     * @notice Calculate discounted price
     * @param basePrice Original ticket price
     * @param discountBPS Discount in basis points
     * @return discountedPrice Price after discount
     */
    function applyDiscount(
        uint256 basePrice,
        uint256 discountBPS
    ) internal pure returns (uint256 discountedPrice) {
        if (discountBPS > BASIS_POINTS) revert InvalidPercentage();
        return (basePrice * (BASIS_POINTS - discountBPS)) / BASIS_POINTS;
    }

    /**
     * @notice Find applicable tier discount
     * @param tiers Array of tier configurations
     * @param totalTickets User's total ticket count
     * @return discountBPS Highest applicable discount
     */
    function findApplicableTier(
        Structs.TierConfig[] memory tiers,
        uint256 totalTickets
    ) internal pure returns (uint256 discountBPS) {
        if (tiers.length == 0) revert EmptyTierList();

        // Search from highest tier down
        for (uint256 i = tiers.length; i > 0; i--) {
            uint256 index = i - 1;
            if (totalTickets >= tiers[index].requiredTickets) {
                return tiers[index].discountBPS;
            }
        }
        return 0;
    }

    // -----------------------------
    // Safety-Checked Conversions
    // -----------------------------

    /**
     * @notice Safely convert to uint96 for Chainlink VRF
     * @param value Input value
     * @return converted Safely casted value
     */
    function safeUint96(
        uint256 value
    ) internal pure returns (uint96 converted) {
        converted = value.toUint96();
        require(value == converted, "Value exceeds uint96 range");
    }
}
