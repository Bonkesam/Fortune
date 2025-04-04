// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title Lottery Data Structures
 * @notice Central repository for all protocol structs
 * @dev Maintains consistent data formats across contracts
 */
library Structs {
    // -----------------------------
    // Core Lottery Structures
    // -----------------------------

    /// @notice Draw lifecycle management
    /// @param startTime Block timestamp of draw start
    /// @param endTime Scheduled end timestamp
    /// @param tickets Array of ticket IDs in draw
    /// @param participants Addresses of current players
    /// @param phase Current draw phase
    /// @param requestId Chainlink VRF request ID
    /// @param winningNumbers Final winning ticket IDs
    struct Draw {
        uint256 startTime;
        uint256 endTime;
        uint256[] tickets;
        address[] participants;
        uint8 phase;
        uint256 requestId;
        uint256[] winningNumbers;
    }

    /// @notice VRF request tracking
    /// @param drawId Associated lottery draw
    /// @param fulfilled Completion status
    /// @param randomWords Generated random values
    struct VRFRequest {
        uint256 drawId;
        bool fulfilled;
        uint256[] randomWords;
    }

    /// @notice NFT ticket metadata
    /// @param rarity 0 = normal, 1 = golden
    /// @param drawId Associated draw ID
    /// @param mintTimestamp Creation block timestamp
    struct TicketTraits {
        uint256 rarity;
        uint256 drawId;
        uint256 mintTimestamp;
    }

    // -----------------------------
    // Prize Pool Structures
    // -----------------------------

    /// @notice Prize distribution configuration
    /// @param grandPrize Percentage for main winner (basis points)
    /// @param secondaryPrizes Percentage for secondary winners
    /// @param daoShare Percentage for treasury
    struct PrizeDistribution {
        uint256 grandPrize;
        uint256 secondaryPrizes;
        uint256 daoShare;
    }

    /// @notice Yield strategy configuration
    /// @param yieldToken Deposit receipt token
    /// @param yieldProtocol Integration address
    /// @param isActive Strategy status
    struct YieldConfig {
        address yieldToken;
        address yieldProtocol;
        bool isActive;
    }

    // -----------------------------
    // Loyalty System Structures
    // -----------------------------

    /// @notice Tiered reward configuration
    /// @param requiredTickets Tickets needed for tier
    /// @param discountBPS Discount in basis points
    struct TierConfig {
        uint256 requiredTickets;
        uint256 discountBPS;
    }
}
